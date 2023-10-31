// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

contract QuarkStateManager {
    error InvalidNonce();
    error NoNonceActive();
    error NoUnusedNonces();
    error NonceAlreadySet();
    error NonceScriptMismatch();

    /// @notice Bit-packed nonce values
    mapping(address /* wallet */ => mapping(uint256 /* bucket */ => uint256 /* bitset */)) public nonces;

    /// @notice Currently active nonce for a wallet, if any, for which storage is accessible
    mapping(address /* wallet */ => uint256 /* nonce */) internal activeNonce;

    /// @notice Per-wallet-nonce storage space that can be utilized while a nonce is active
    mapping(address /* wallet */ => mapping(uint256 /* nonce */ => mapping(bytes32 /* key */ => bytes32 /* storage */)))
        internal walletStorage;

    /// @notice Per-wallet-nonce callback hash for preventing replays with changed code
    mapping(address /* wallet */ => mapping(uint256 /* nonce */ => bytes32 /* callback hash */)) nonceCallback;

    /**
     * @notice Return whether a nonce has been exhausted; note that if a nonce is not set, that does not mean it has not been used before
     * @dev `0` is not a valid nonce
     * @param wallet Address of the wallet owning the nonce
     * @param nonce Nonce to check
     * @return Whether the nonce has been exhausted
     */
    function isNonceSet(address wallet, uint256 nonce) public view returns (bool) {
        if (nonce == 0) {
            revert InvalidNonce();
        }
        uint256 bucket = nonce >> 8;
        uint256 mask = 1 << (nonce & 0xff);
        return nonces[wallet][bucket] & mask != 0;
    }

    /**
     * @notice Returns the next valid unset nonce for a given wallet (note that 0 is not a valid nonce)
     * @dev Any unset nonce > 0 is valid to use, but using this method
     * increases the likelihood that the nonce you use will be in a bucket that
     * has already been written to, which costs less gas
     * @return The next unused nonce
     */
    function nextNonce(address wallet) external view returns (uint256) {
        uint256 i;
        for (i = 1; i < type(uint256).max; i++) {
            if (!isNonceSet(wallet, i)) {
                return i;
            }
        }
        revert NoUnusedNonces();
    }

    /**
     * @notice Return the nonce currently active for a wallet; revert if none
     * @return Currently active nonce
     */
    function getActiveNonce() external view returns (uint256) {
        if (activeNonce[msg.sender] == 0) {
            revert NoNonceActive();
        }
        return activeNonce[msg.sender];
    }

    /**
     * @dev Locate a nonce at a (bucket, mask) bitset position in the nonces mapping
     */
    function getBucket(uint256 nonce) internal pure returns (uint256, /* bucket */ uint256 /* mask */ ) {
        if (nonce == 0) {
            revert InvalidNonce();
        }
        uint256 bucket = nonce >> 8;
        uint256 setMask = 1 << (nonce & 0xff);
        return (bucket, setMask);
    }

    /**
     * @notice Clears (un-sets) the active nonce to allow its reuse; allows a script to be replayed
     */
    function clearNonce() external {
        if (activeNonce[msg.sender] == 0) {
            revert NoNonceActive();
        }
        (uint256 bucket, uint256 setMask) = getBucket(activeNonce[msg.sender]);
        nonces[msg.sender][bucket] &= ~setMask;
    }

    /**
     * @notice Set a wallet nonce as the active nonce and yield control back to the wallet by calling into callback
     * @param nonce Nonce to activate for the transaction
     * @dev The script is expected to clearNonce() if it wishes to be replayable
     */
    function setActiveNonceAndCallback(uint256 nonce, bytes calldata callback) external returns (bytes memory) {
        if (nonce == 0) {
            revert InvalidNonce();
        }

        // retrieve the (bucket, mask) pair that addresses the nonce in memory
        (uint256 bucket, uint256 setMask) = getBucket(nonce);

        // ensure nonce is not already set (NOTE: inlined isNonceSet to avoid reading the nonce twice)
        if ((nonces[msg.sender][bucket] & setMask) != 0) {
            revert NonceAlreadySet();
        }

        // spend the nonce; only if the callee chooses to clear it will it get un-set and become replayable
        nonces[msg.sender][bucket] |= setMask;

        // if the nonce has been used before, check if the callback hash matches
        bytes32 callbackHash = keccak256(callback);
        if ((nonceCallback[msg.sender][nonce] != bytes32(0)) && (nonceCallback[msg.sender][nonce] != callbackHash)) {
            // if callback does not match, but scriptAddress points to the empty code, cancel the nonce
            address scriptAddress = abi.decode(callback[4:], (address));
            if (scriptAddress.code.length == 0) {
                return hex"";
            }
            // if for any other reason the callback does not match, revert
            revert NonceScriptMismatch();
        }

        // set the nonce active and yield to the wallet callback
        uint256 previousNonce = activeNonce[msg.sender];
        activeNonce[msg.sender] = nonce;

        (bool success, bytes memory result) = msg.sender.call(callback);
        // if the call fails, propagate the revert from the wallet
        if (!success) {
            assembly {
                revert(add(result, 0x20), mload(result))
            }
        }

        // if a nonce was cleared, set the nonceScript to lock nonce re-use to the same script address
        if ((nonces[msg.sender][bucket] & setMask) == 0) {
            nonceCallback[msg.sender][nonce] = callbackHash;
        }

        // release the nonce when the wallet finishes executing callback
        activeNonce[msg.sender] = previousNonce;

        // otherwise, return the result. currently, result is double-encoded. un-encode it.
        return abi.decode(result, (bytes));
    }

    /**
     * @notice Write arbitrary bytes to storage namespaced by the currently active nonce; reverts if no nonce is currently active
     */
    function write(bytes32 key, bytes32 value) external {
        if (activeNonce[msg.sender] == 0) {
            revert NoNonceActive();
        }
        walletStorage[msg.sender][activeNonce[msg.sender]][key] = value;
    }

    /**
     * @notice Read from storage namespaced by the currently active nonce; reverts if no nonce is currently active
     * @return Value at the nonce storage location, as bytes
     */
    function read(bytes32 key) external returns (bytes32) {
        if (activeNonce[msg.sender] == 0) {
            revert NoNonceActive();
        }
        return walletStorage[msg.sender][activeNonce[msg.sender]][key];
    }
}
