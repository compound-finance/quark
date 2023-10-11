// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { CodeJar } from "./CodeJar.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

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
    error SignatureExpired();

    /// @notice Address of the EOA that controls this wallet
    address public immutable owner;

    /// @notice address of the currently pending callback script
    address public callback;

    /// @notice storage slot for storing the active `callback` address
    bytes32 internal constant ACTIVE_CALLBACK_SLOT = bytes32(keccak256("org.quark.active-callback"));

    /// @dev The EIP-712 typehash for authorizing an operation
    bytes32 internal constant QUARK_OPERATION_TYPEHASH = keccak256("QuarkOperation(bytes scriptSource,bytes scriptCalldata,uint256 nonce,uint256 expiry,bool allowCallback)");

    /// @dev The EIP-712 typehash for the contract's domain
    bytes32 internal constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @notice Name of contract, for use in DOMAIN_SEPARATOR
    string public constant name = "Quark Wallet";

    /// @notice The major version of this contract, for use in DOMAIN_SEPARATOR
    string public constant VERSION = "1";

    /// @notice Bit-packed nonce values
    mapping(uint256 => uint256) public nonces;

    /// @notice Address of CodeJar contract used to save transaction script source code
    CodeJar public codeJar;

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
        // requirements
        // isReplayable
    }

    constructor(address owner_, CodeJar codeJar_) {
        owner = owner_;
        codeJar = codeJar_;
        /*
         * translation note: we cannot directly access OWNER_SLOT within
         * an inline assembly block, for seemingly arbitrary reasons;
         * therefore, we copy the immutable slot addresse into a local
         * variable that we are allowed to access with impunity.
         */
        bytes32 slot = OWNER_SLOT;
        assembly { sstore(slot, owner_) }
    }

    /**
     * @notice Return whether a nonce has been set
     * @param nonce The nonce to check
     * @return Whether the nonce has been set
     */
    function isSet(uint256 nonce) public view returns (bool) {
        uint256 bucket = nonce >> 8;
        uint256 mask = 1 << (nonce & 0xff);
        return nonces[bucket] & mask != 0;
    }

    /**
     * @dev Set or unset `nonce`
     */
    function setNonce(uint256 nonce) internal {
        uint256 bucket = nonce >> 8;
        uint256 mask = 1 << (nonce & 0xff);
        nonces[bucket] |= mask;
    }

    /**
     * @notice Returns the next unset nonce for this wallet
     * @dev Any unset nonce is valid to use, but using this method increases
     * the likelihood that the nonce you use will be on a bucket that has
     * already been written to, which costs less gas
     * @return The next unused nonce
     */
    function nextUnusedNonce() external returns (uint256) {
        uint256 i;
        for (i = 0; i < type(uint256).max; i++) {
            if (!isSet(i)) return i;
        }

        revert NoUnusedNonces();
    }

    /**
     * @notice Returns the domain separator used for signing operation
     * @return bytes32 The domain separator
     */
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH, keccak256(bytes(name)), keccak256(bytes(VERSION)), block.chainid, address(this)
            )
        );
    }

    /**
     * @dev Returns the current active callback script address.
     */
    function getActiveCallback() internal returns (address) {
        bytes32 slot = ACTIVE_CALLBACK_SLOT;
        address callback;
        assembly { callback := sload(slot) }
        return callback;
    }

    /**
     * @dev Sets the current active callback script address. This is the
     *  address of the currently-running transaction script that expects to
     *  receive a callback, which will be handled by the wallet's fallback
     *  function.
     */
    function setActiveCallback(address callback) internal {
        bytes32 slot = ACTIVE_CALLBACK_SLOT;
        assembly { sstore(slot, callback) }
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
    function executeQuarkOperation(
        QuarkOperation calldata op,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public payable returns (bytes memory) {
        if (block.timestamp >= op.expiry) revert SignatureExpired();
        if (isSet(op.nonce)) revert InvalidNonce();

        bytes32 structHash = keccak256(abi.encode(QUARK_OPERATION_TYPEHASH, op.scriptSource, op.scriptCalldata, op.nonce, op.expiry, op.allowCallback));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));

        if (isValidSignature(owner, digest, v, r, s)) {
            setNonce(op.nonce);
            // XXX handle op.scriptAddress without CodeJar
            address scriptAddress = codeJar.saveCode(op.scriptSource);

            bytes memory result = executeQuarkOperationInternal(scriptAddress, op.scriptCalldata, op.allowCallback);

            return result;
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
     * @notice Store or lookup the operation script and invoke it with the
     * given encoded calldata
     * @param scriptSource Source code of the transaction script to execute
     * @param scriptCalldata The encoded function selector and arguments to call on the transaction script
     * @return return value from the executed operation
     */
    function executeQuarkOperation(bytes calldata scriptSource, bytes calldata scriptCalldata) public payable returns (bytes memory) {
        // XXX authenticate caller
        address scriptAddress = codeJar.saveCode(scriptSource);
        // XXX add support for allowCallback to the direct path
        return executeQuarkOperationInternal(scriptAddress, scriptCalldata, false);
    }

    /**
     * @dev Execute QuarkOperation
     */
    function executeQuarkOperationInternal(address scriptAddress, bytes memory scriptCalldata, bool allowCallback) internal returns (bytes memory) {
        uint256 codeLen;
        assembly {
            codeLen := extcodesize(scriptAddress)
        }
        if (codeLen == 0) {
            revert QuarkCodeNotFound();
        }

        // if the script allows callbacks, set it as the current callback
        if (allowCallback) {
            address callback = getActiveCallback();
            if (callback != address(0)) {
                revert QuarkCallbackAlreadyActive();
            }
            setActiveCallback(scriptAddress);
        }

        bool success;
        uint returnSize;
        uint scriptCalldataLen = scriptCalldata.length;
        assembly {
            success := callcode(gas(), scriptAddress, 0/* value */, add(scriptCalldata, 0x20), scriptCalldataLen, 0x0, 0)
            returnSize := returndatasize()
        }

        setActiveCallback(address(0));

        bytes memory returnData = new bytes(returnSize);
        assembly {
            returndatacopy(add(returnData, 0x20), 0x00, returnSize)
        }
        if (!success) {
            revert QuarkCallError(returnData);
        }

        return returnData;
    }

    fallback(bytes calldata data) external returns (bytes memory) {
        address callback = getActiveCallback();
        if (callback != address(0)) {
            (, bytes memory result) = callback.delegatecall(data);
            return result;
        } else {
            revert NoActiveCallback();
        }
    }
}
