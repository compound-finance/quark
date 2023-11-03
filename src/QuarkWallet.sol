// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {CodeJar} from "./CodeJar.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {QuarkStateManager} from "./QuarkStateManager.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

contract QuarkWallet is IERC1271 {
    error BadSignatory();
    error InvalidEIP1271Signature();
    error InvalidNonce();
    error InvalidSignature();
    error InvalidSignatureS();
    error NoActiveCallback();
    error QuarkCallError(bytes);
    error QuarkCodeNotFound();
    error SignatureExpired();
    error Unauthorized();

    /// @notice Address of the EOA signer or the EIP-1271 contract that verifies signed operations for this wallet
    address public immutable signer;

    /// @notice Address of the executor contract, if any, empowered to direct-execute unsigned operations for this wallet
    address public immutable executor;

    /// @notice Address of CodeJar contract used to save transaction script source code
    CodeJar public immutable codeJar;

    /// @notice Address of QuarkStateManager contract that manages nonces and nonce-namespaced transaction script storage
    QuarkStateManager public immutable stateManager;

    /// @notice Well-known storage location for the currently executing script's callback address (if any)
    bytes32 internal constant CALLBACK_KEY = keccak256("callback.v1.quark");

    /// @dev The EIP-712 typehash for authorizing an operation
    bytes32 internal constant QUARK_OPERATION_TYPEHASH = keccak256(
        "QuarkOperation(address scriptAddress,bytes scriptSource,bytes scriptCalldata,uint256 nonce,uint256 expiry,bool allowCallback)"
    );

    /// @dev The EIP-712 typehash for the contract's domain
    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @notice Name of contract, for use in DOMAIN_SEPARATOR
    string public constant name = "Quark Wallet";

    /// @notice The major version of this contract, for use in DOMAIN_SEPARATOR
    string public constant VERSION = "1";

    /// @notice The magic value to return for valid ERC1271 signature
    bytes4 internal constant EIP_1271_MAGIC_VALUE = 0x1626ba7e;

    struct QuarkOperation {
        // TODO: potential optimization: re-order struct for more efficient packing
        // Can be set as address(0) if using `scriptSource`
        address scriptAddress; // The address of the transaction script to run
        // Can be set as empty bytes if using `scriptAddress`
        bytes scriptSource; // The runtime bytecode of the transaction script to run
        bytes scriptCalldata; // selector + arguments encoded as calldata
        uint256 nonce;
        uint256 expiry;
        bool allowCallback;
    }

    constructor(address signer_, address executor_, CodeJar codeJar_, QuarkStateManager stateManager_) {
        signer = signer_;
        executor = executor_;
        codeJar = codeJar_;
        stateManager = stateManager_;
    }

    /**
     * @notice Returns the next unset nonce for this wallet
     * @dev Any unset nonce is valid to use, but using this method increases
     * the likelihood that the nonce you use will be on a bucket that has
     * already been written to, which costs less gas
     * @return The next unused nonce
     */
    function nextNonce() external view returns (uint256) {
        return stateManager.nextNonce(address(this));
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
     * @dev Can only be called with signatures from the wallet's signer
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
        if (stateManager.isNonceSet(address(this), op.nonce)) {
            revert InvalidNonce();
        }

        bytes32 structHash = keccak256(
            abi.encode(
                QUARK_OPERATION_TYPEHASH,
                op.scriptAddress,
                op.scriptSource,
                op.scriptCalldata,
                op.nonce,
                op.expiry,
                op.allowCallback
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));

        if (isValidSignatureInternal(signer, digest, v, r, s)) {
            address scriptAddress = op.scriptAddress;
            if (scriptAddress == address(0)) {
                scriptAddress = codeJar.saveCode(op.scriptSource);
            }
            return stateManager.setActiveNonceAndCallback(
                op.nonce,
                abi.encodeCall(
                    this.executeQuarkOperationWithNonceLock, (scriptAddress, op.scriptCalldata, op.allowCallback)
                )
            );
        } else {
            revert InvalidSignature();
        }
    }

    /**
     * @notice Execute a transaction script directly
     * @dev Can only be called by the wallet's signer or executor
     * @param nonce Nonce for the operation; must be unused
     * @param scriptAddress Address for the script to execute
     * @param scriptCalldata Encoded call to invoke on the script
     * @param allowCallback Whether the script allows callbacks
     * @return Return value from the executed operation
     */
    function executeScript(uint256 nonce, address scriptAddress, bytes calldata scriptCalldata, bool allowCallback)
        public
        payable
        returns (bytes memory)
    {
        // only allow the signer or the executor for the wallet to use unsigned execution
        if (!(msg.sender == signer || msg.sender == executor)) {
            revert Unauthorized();
        }
        return stateManager.setActiveNonceAndCallback(
            nonce,
            abi.encodeCall(this.executeQuarkOperationWithNonceLock, (scriptAddress, scriptCalldata, allowCallback))
        );
    }

    /**
     * @notice Checks whether an EIP-1271 signature is valid
     * @dev If the QuarkWallet is owned by an EOA, isValidSignature confirms
     * that the signature comes from the signer; if the QuarkWallet is owned by
     * a smart contract, isValidSignature relays the `isValidSignature` to the
     * smart contract
     * @param hash Hash of the signed data
     * @param signature Signature byte array associated with data
     * @return bytes4 Returns the ERC-1271 "magic value" that indicates that the signature is valid
     */
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4) {
        if (signature.length != 65) revert InvalidSignature();
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
        if (isValidSignatureInternal(signer, hash, v, r, s)) {
            return EIP_1271_MAGIC_VALUE;
        } else {
            revert InvalidSignature();
        }
    }

    /*
     * @dev If the QuarkWallet is owned by an EOA, isValidSignature confirms
     * that the signature comes from the signer; if the QuarkWallet is owned by
     * a smart contract, isValidSignature relays the `isValidSignature` to the
     * smart contract; if the smart contract that owns the wallet has no code,
     * the signature will be treated as an EIP-712 signature and revert
     */
    function isValidSignatureInternal(address signatory, bytes32 digest, uint8 v, bytes32 r, bytes32 s)
        internal
        view
        returns (bool)
    {
        // a contract deployed with empty code will be treated as an EOA and will revert
        if (signatory.code.length > 0) {
            bytes memory signature = abi.encodePacked(r, s, v);
            (bool success, bytes memory data) =
                signatory.staticcall(abi.encodeWithSelector(EIP_1271_MAGIC_VALUE, digest, signature));
            if (!success) revert InvalidEIP1271Signature();
            bytes4 returnValue = abi.decode(data, (bytes4));
            return returnValue == EIP_1271_MAGIC_VALUE;
        } else {
            (address recoveredSigner, ECDSA.RecoverError recoverError) = ECDSA.tryRecover(digest, v, r, s);
            if (recoverError == ECDSA.RecoverError.InvalidSignatureS) revert InvalidSignatureS();
            if (recoverError == ECDSA.RecoverError.InvalidSignature) revert BadSignatory();
            if (recoveredSigner != signatory) revert BadSignatory();
            return true;
        }
    }

    /**
     * @notice Execute a QuarkOperation with its nonce locked and with access to private nonce-scoped storage.
     * @dev Must be called by stateManager as the yieldTarget of an acquireNonceAndYield call
     * @param scriptAddress Address of script to execute
     * @param scriptCalldata Encoded calldata for the call to execute on the scriptAddress
     * @param allowCallback Whether the transaction script should allow callbacks from outside contracts
     * @return Result of executing the script, encoded as bytes
     */
    function executeQuarkOperationWithNonceLock(address scriptAddress, bytes memory scriptCalldata, bool allowCallback)
        public
        returns (bytes memory)
    {
        require(msg.sender == address(stateManager));
        uint256 codeLen;
        assembly {
            codeLen := extcodesize(scriptAddress)
        }
        if (codeLen == 0) {
            revert QuarkCodeNotFound();
        }

        // if the script allows callbacks, set it as the current callback
        if (allowCallback) {
            stateManager.write(CALLBACK_KEY, bytes32(uint256(uint160(scriptAddress))));
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

        if (allowCallback) {
            stateManager.write(CALLBACK_KEY, bytes32(uint256(0)));
        }

        if (!success) {
            revert QuarkCallError(returnData);
        }

        return returnData;
    }

    fallback(bytes calldata data) external returns (bytes memory) {
        address callback = address(uint160(uint256(stateManager.read(CALLBACK_KEY))));
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
