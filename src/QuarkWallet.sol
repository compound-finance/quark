// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {CodeJar} from "./CodeJar.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {QuarkStorageManager} from "./QuarkStorageManager.sol";

contract QuarkWallet {
    error BadSignatory();
    error InvalidNonce();
    error InvalidSignatureS();
    error NoActiveCallback();
    error NoUnusedNonces();
    error QuarkCallbackAlreadyActive();
    error QuarkCallError(bytes);
    error QuarkCodeNotFound();
    error QuarkNonceReplay(uint256);
    error QuarkReadError();
    error RequirementNotMet();
    error SignatureExpired();

    /// @notice Address of the EOA that controls this wallet
    address public immutable owner;

    /// @notice Address of CodeJar contract used to save transaction script source code
    CodeJar public immutable codeJar;

    /// @notice Address of QuarkStorageManager contract that manages nonces and nonce-namespaced transaction script storage
    QuarkStorageManager public immutable storageManager;

    /// @dev The EIP-712 typehash for authorizing an operation
    bytes32 internal constant QUARK_OPERATION_TYPEHASH = keccak256(
        "QuarkOperation(bytes scriptSource,bytes scriptCalldata,uint256 nonce,uint256 expiry,bool allowCallback,bool isReplayable,uint256[] requirements)"
    );

    /// @dev The EIP-712 typehash for the contract's domain
    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @notice Name of contract, for use in DOMAIN_SEPARATOR
    string public constant name = "Quark Wallet";

    /// @notice The major version of this contract, for use in DOMAIN_SEPARATOR
    string public constant VERSION = "1";

    /// @notice Bit-packed nonce values
    mapping(uint256 => uint256) public nonces;

    struct QuarkOperation {
        /* TODO: optimization: allow passing in the address of the script
         * to run, instead of the calldata for defining the script.
         */
        // address scriptAddress;
        bytes scriptSource;
        bytes scriptCalldata; // selector + arguments encoded as calldata
        uint256 nonce;
        uint256 expiry;
        bool allowCallback;
        bool isReplayable;
        uint256[] requirements;
    }

    constructor(address owner_, CodeJar codeJar_, QuarkStorageManager storageManager_) {
        owner = owner_;
        codeJar = codeJar_;
        storageManager = storageManager_;
    }

    /**
     * @notice Returns the next unset nonce for this wallet
     * @dev Any unset nonce is valid to use, but using this method increases
     * the likelihood that the nonce you use will be on a bucket that has
     * already been written to, which costs less gas
     * @return The next unused nonce
     */
    function nextUnusedNonce() external view returns (uint256) {
        return storageManager.nextUnusedNonce(address(this));
    }

    /**
     * @notice Returns the domain separator used for signing operation
     * @return bytes32 The domain separator
     */
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), keccak256(bytes(VERSION)), block.chainid, address(this))
        );
    }

    /**
     * @notice Execute a QuarkOperation via signature
     * @dev Can only be called with signatures from the wallet's owner
     * @param op A QuarkOperation struct
     * @param v EIP-712 signature v value
     * @param r EIP-712 signature r value
     * @param s EIP-712 signature s value
     * @return return value from the executed operation
     */
    function executeQuarkOperation(QuarkOperation calldata op, uint8 v, bytes32 r, bytes32 s)
        public
        payable
        returns (bytes memory)
    {
        if (block.timestamp >= op.expiry) {
            revert SignatureExpired();
        }
        if (storageManager.isNonceSet(address(this), op.nonce)) {
            revert InvalidNonce();
        }

        bytes32 structHash = keccak256(
            abi.encode(
                QUARK_OPERATION_TYPEHASH,
                op.scriptSource,
                op.scriptCalldata,
                op.nonce,
                op.expiry,
                op.allowCallback,
                op.isReplayable,
                op.requirements
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));

        if (isValidSignature(owner, digest, v, r, s)) {
            for (uint256 i; i < op.requirements.length; i++) {
                if (!storageManager.isNonceSet(address(this), op.requirements[i])) {
                    revert RequirementNotMet();
                }
            }
            // XXX handle op.scriptAddress without CodeJar
            address scriptAddress = codeJar.saveCode(op.scriptSource);
            bool isReplayable = op.isReplayable;
            bool allowCallback = op.allowCallback;
            return storageManager.acquireNonceAndYield(
                op.nonce,
                abi.encodeCall(
                    this.executeQuarkOperationWithNonceLock, (scriptAddress, op.scriptCalldata, allowCallback, isReplayable)
                )
            );
        }
    }

    /**
     * @dev Validates EIP-712 signature
     */
    function isValidSignature(address signer, bytes32 digest, uint8 v, bytes32 r, bytes32 s)
        internal
        pure
        returns (bool)
    {
        (address recoveredSigner, ECDSA.RecoverError recoverError) = ECDSA.tryRecover(digest, v, r, s);

        if (recoverError == ECDSA.RecoverError.InvalidSignatureS) revert InvalidSignatureS();
        if (recoverError == ECDSA.RecoverError.InvalidSignature) revert BadSignatory();
        if (recoveredSigner != signer) revert BadSignatory();

        return true;
    }

    /**
     * @notice Execute a QuarkOperation with its nonce locked and with access to private nonce-scoped storage.
     * @dev Must be called by storageManager as the yieldTarget of an acquireNonceAndYield call
     * @param scriptAddress Address of script to execute
     * @param scriptCalldata Encoded calldata for the call to execute on the scriptAddress
     * @param allowCallback Whether the transaction script should allow callbacks from outside contracts
     * @return Result of executing the script, encoded as bytes
     */
    function executeQuarkOperationWithNonceLock(address scriptAddress, bytes memory scriptCalldata, bool allowCallback, bool isReplayable)
        public
        returns (bytes memory)
    {
        uint256 codeLen;
        assembly {
            codeLen := extcodesize(scriptAddress)
        }
        if (codeLen == 0) {
            revert QuarkCodeNotFound();
        }

        // if the script allows callbacks, set it as the current callback
        if (allowCallback) {
            address callback = storageManager.getProxyTarget();
            if (callback != address(0)) {
                revert QuarkCallbackAlreadyActive();
            }
            storageManager.setProxyTarget(scriptAddress);
        }

        bool success;
        uint256 returnSize;
        uint256 scriptCalldataLen = scriptCalldata.length;
        assembly {
            success :=
                callcode(gas(), scriptAddress, 0, /* value */ add(scriptCalldata, 0x20), scriptCalldataLen, 0x0, 0)
            returnSize := returndatasize()
        }

        bytes memory returnData = new bytes(returnSize);
        assembly {
            returndatacopy(add(returnData, 0x20), 0x00, returnSize)
        }

        storageManager.setProxyTarget(address(0));

        if (!success) {
            revert QuarkCallError(returnData);
        }

        if (!isReplayable) {
            storageManager.setNonce(storageManager.getAcquiredNonce());
        }

        return returnData;
    }

    fallback(bytes calldata data) external returns (bytes memory) {
        address callback = storageManager.getProxyTarget();
        if (callback != address(0)) {
            (bool success, bytes memory result) = callback.delegatecall(data);
            if (!success) {
                assembly {
                    let size := mload(result)
                    revert(add(result, 0x20), size)
                }
            }
            return result;
        } else {
            revert NoActiveCallback();
        }
    }
}
