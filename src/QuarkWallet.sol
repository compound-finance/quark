// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./CodeJar.sol";

contract QuarkWallet {
    address public immutable owner;
    address public immutable relayer;

    bytes32 public constant OWNER_SLOT   = bytes32(keccak256("org.quark.owner"));
    bytes32 public constant RELAYER_SLOT = bytes32(keccak256("org.quark.relayer"));

    error QuarkReadError();
    error QuarkCallError();
    error QuarkBadCode();

    CodeJar public codeJar;

    struct QuarkOperation {
        // TODO: optimization: allow passing in the address of the script
        // o run, instead of the calldata for defining the script.
        // address codeAddress;
        bytes code;
        bytes encodedCalldata; // selector + arguments encoded as calldata
    }

    constructor(address owner_, CodeJar codeJar_) {
        owner = owner_;
        codeJar = codeJar_;
        /*
         * translation note: caller() is msg.sender because origin() is
         * tx.origin, and semantically msg.sender makes more sense as
         * caller since that's the caller in the current context.
         */
        relayer = msg.sender;
        /*
         * translation note: we cannot directly access OWNER_SLOT or
         * RELAYER_SLOT within an inline assembly block, for arbitrary and
         * stupid reasons; therefore, we copy the immutable slot addresses
         * into a local variable that we are allowed to access with
         * impunity.
         */
        bytes32 slot = OWNER_SLOT;
        assembly { sstore(slot, owner_) }
        slot = RELAYER_SLOT;
        assembly { sstore(slot, caller()) }
    }

    /**
     * @notice store or lookup the operation script and invoke it with the
     * given encoded calldata
     */
    function executeQuarkOperation(QuarkOperation calldata op) public payable returns (bytes memory) {
        address deployedCode = codeJar.saveCode(op.code);
        uint256 codeLen;
        assembly {
            codeLen := extcodesize(deployedCode)
        }
        if (codeLen == 0) {
            revert QuarkBadCode();
        }

        (bool success, bytes memory result) = deployedCode.delegatecall(
            op.encodedCalldata
        );
        if (!success) {
            revert QuarkCallError();
        }
        return result;
    }

    /**
     * @notice read the quark code address from the relayer and
     * delegatecall the code pointed thereto passing the given calldata.
     */
    fallback(bytes calldata quarkCalldata) external payable returns (bytes memory) {
        (bool success0, bytes memory rawCode) = relayer.call(
            abi.encodeWithSignature("readQuarkCodeAddress()")
        );
        if (!success0) {
            revert QuarkReadError();
        }
        (address code) = abi.decode(rawCode, (address));
        (bool success1, bytes memory result) = code.delegatecall(
            quarkCalldata
        );
        if (!success1) {
            assembly {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
        return result;
    }
}
