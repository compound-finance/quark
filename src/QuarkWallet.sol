// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./CodeJar.sol";

contract QuarkWallet {
    error QuarkReadError();
    error QuarkCallError(bytes);
    error QuarkCodeNotFound();
    error QuarkNonceReplay(uint256);

    address public immutable owner;

    bytes32 public constant OWNER_SLOT = bytes32(keccak256("org.quark.owner"));

    mapping(uint256 => uint256) public nonces;

    CodeJar public codeJar;

    struct QuarkOperation {
        /* TODO: optimization: allow passing in the address of the script
         * to run, instead of the calldata for defining the script.
         */
        // address scriptAddress;
        bytes scriptSource;
        bytes scriptCalldata; // selector + arguments encoded as calldata
        uint256 nonce;
    }

    constructor(address owner_, CodeJar codeJar_) {
        owner = owner_;
        codeJar = codeJar_;
        /*
         * translation note: we cannot directly access OWNER_SLOT within
         * an inline assembly block, for arbitrary and stupid reasons;
         * therefore, we copy the immutable slot addresse into a local
         * variable that we are allowed to access with impunity.
         */
        bytes32 slot = OWNER_SLOT;
        assembly { sstore(slot, owner_) }
    }

    /**
     * @notice for a uint256 nonce return the nonce bucket and the mask for selecting the nonce in the bucket.
     */
    function locateNonce(uint256 nonce) internal view returns (uint256, uint256) {
        uint256 bucketIndex = nonce / 256;
        uint256 bitIndex = nonce - (bucketIndex * 256);
        uint256 selector = (1 << bitIndex);
        return (bucketIndex, selector);
    }

    /**
     * @notice acquire the nonce for an operation. A non-replayable operation will exclusively acquire the nonce,
     * marking it used; a replayable operation may acquire the same nonce multiple times until a condition is met.
     */
    function acquireNonce(QuarkOperation calldata op) internal {
        (uint256 bucket, uint256 selector) = locateNonce(op.nonce);
        // if the nonce has been used, revert
        if ((nonces[bucket] & selector) >= 1) {
            revert QuarkNonceReplay(op.nonce);
        }
        // TODO: if op.replayable, do not mark the nonce used
        nonces[bucket] |= selector;
    }

    /**
     * @notice store or lookup the operation's script and call it with the given calldata.
     */
    function executeQuarkOperation(QuarkOperation calldata op) public payable returns (bytes memory) {
        acquireNonce(op);
        address deployedCode = codeJar.saveCode(op.scriptSource);
        uint256 codeLen;
        assembly {
            codeLen := extcodesize(deployedCode)
        }
        if (codeLen == 0) {
            revert QuarkCodeNotFound();
        }

        (bool success, bytes memory result) = deployedCode.delegatecall(
            op.scriptCalldata
        );
        if (!success) {
            revert QuarkCallError(result);
        }
        return result;
    }
}
