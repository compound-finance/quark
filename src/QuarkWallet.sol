// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./CodeJar.sol";

contract QuarkWallet {
    error QuarkReadError();
    error QuarkCallError(bytes);
    error QuarkCodeNotFound();

    address public immutable owner;

    bytes32 public constant OWNER_SLOT = bytes32(keccak256("org.quark.owner"));

    CodeJar public codeJar;

    struct QuarkOperation {
        /* TODO: optimization: allow passing in the address of the script
         * o run, instead of the calldata for defining the script.
         * address codeAddress;
         */
        bytes code;
        bytes encodedCalldata; // selector + arguments encoded as calldata
    }

    constructor(address owner_, CodeJar codeJar_) {
        owner = owner_;
        codeJar = codeJar_;
        /*
         * translation note: we cannot directly access OWNER_SLOT or
         * RELAYER_SLOT within an inline assembly block, for arbitrary and
         * stupid reasons; therefore, we copy the immutable slot addresses
         * into a local variable that we are allowed to access with
         * impunity.
         */
        bytes32 slot = OWNER_SLOT;
        assembly { sstore(slot, owner_) }
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
            revert QuarkCodeNotFound();
        }

        (bool success, bytes memory result) = deployedCode.delegatecall(
            op.encodedCalldata
        );
        if (!success) {
            revert QuarkCallError(result);
        }
        return result;
    }
}
