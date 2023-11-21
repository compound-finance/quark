// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

interface IExecutor {
    function executeScriptWithNonceLock(address scriptAddress, bytes calldata scriptCalldata)
        external
        payable
        returns (bytes memory);
}

/**
 * @title Quark State Manager
 * @notice Contract for managing nonces and storage for Quark wallets, guaranteeing storage isolation across wallets
 *         and Quark operations
 * @author Compound Labs, Inc.
 */
contract QuarkStateManager {
    error NoActiveNonce();
    error NoUnusedNonces();
    error NonceAlreadySet();
    error NonceScriptMismatch();

    /// @notice Bit-packed structure of a nonce-script pair
    struct NonceScript {
        uint96 nonce;
        address scriptAddress;
    }

    /// @notice Bit-packed nonce values
    mapping(address /* wallet */ => mapping(uint256 /* bucket */ => uint256 /* bitset */)) public nonces;

    /// @notice Per-wallet-nonce address for preventing replays with changed script address
    mapping(address /* wallet */ => mapping(uint96 /* nonce */ => address /* address */)) public nonceScriptAddress;

    /// @notice Currently active nonce-script pair for a wallet, if any, for which storage is accessible
    mapping(address /* wallet */ => NonceScript) internal activeNonceScript;

    /// @notice Per-wallet-nonce storage space that can be utilized while a nonce is active
    mapping(address /* wallet */ => mapping(uint96 /* nonce */ => mapping(bytes32 /* key */ => bytes32 /* storage */)))
        internal walletStorage;

    /**
     * @notice Return whether a nonce has been exhausted; note that if a nonce is not set, that does not mean it has not been used before
     * @dev `0` is not a valid nonce
     * @param wallet Address of the wallet owning the nonce
     * @param nonce Nonce to check
     * @return Whether the nonce has been exhausted
     */
    function isNonceSet(address wallet, uint96 nonce) public view returns (bool) {
        (uint256 bucket, uint256 mask) = getBucket(nonce);
        return isNonceSetInternal(wallet, bucket, mask);
    }

    /// @dev Returns if a given nonce is set for a wallet, using the nonce's bucket and mask
    function isNonceSetInternal(address wallet, uint256 bucket, uint256 mask) internal view returns (bool) {
        return (nonces[wallet][bucket] & mask) != 0;
    }

    /**
     * @notice Returns the next valid unset nonce for a given wallet (note that 0 is not a valid nonce)
     * @dev Any unset nonce > 0 is valid to use, but using this method
     * increases the likelihood that the nonce you use will be in a bucket that
     * has already been written to, which costs less gas
     * @return The next unused nonce
     */
    function nextNonce(address wallet) external view returns (uint96) {
        for (uint96 i = 0; i < type(uint96).max;) {
            if (!isNonceSet(wallet, i) && (nonceScriptAddress[wallet][i] == address(0))) {
                return i;
            }

            unchecked {
                ++i;
            }
        }
        revert NoUnusedNonces();
    }

    /**
     * @notice Return the script address associated with the currently active nonce; revert if none
     * @return Currently active script address
     */
    function getActiveScript() external view returns (address) {
        if (activeNonceScript[msg.sender].scriptAddress == address(0)) {
            revert NoActiveNonce();
        }
        // the last 20 bytes is the address
        return activeNonceScript[msg.sender].scriptAddress;
    }

    /// @dev Locate a nonce at a (bucket, mask) bitset position in the nonces mapping
    function getBucket(uint96 nonce) internal pure returns (uint256, /* bucket */ uint256 /* mask */ ) {
        uint256 bucket = nonce >> 8;
        uint256 setMask = 1 << (nonce & 0xff);
        return (bucket, setMask);
    }

    /// @notice Clears (un-sets) the active nonce to allow its reuse; allows a script to be replayed
    function clearNonce() external {
        if (activeNonceScript[msg.sender].scriptAddress == address(0)) {
            revert NoActiveNonce();
        }
        (uint256 bucket, uint256 setMask) = getBucket(activeNonceScript[msg.sender].nonce);
        nonces[msg.sender][bucket] &= ~setMask;
    }

    /**
     * @notice Set a given nonce for the calling wallet; effectively cancels any replayable script using that nonce
     * @param nonce Nonce to set for the calling wallet
     */
    function setNonce(uint96 nonce) external {
        // TODO: should we check whether there exists a nonceScriptAddress?
        (uint256 bucket, uint256 setMask) = getBucket(nonce);
        setNonceInternal(bucket, setMask);
    }

    /// @dev Set a nonce for the msg.sender, using the nonce's bucket and mask
    function setNonceInternal(uint256 bucket, uint256 setMask) internal {
        nonces[msg.sender][bucket] |= setMask;
    }

    /**
     * @notice Set a wallet nonce as the active nonce and yield control back to the wallet by calling into callback
     * @param nonce Nonce to activate for the transaction
     * @param scriptAddress Address of script to invoke with nonce lock
     * @param scriptCalldata Calldata for script call to invoke with nonce lock
     * @dev The script is expected to clearNonce() if it wishes to be replayable
     */
    function setActiveNonceAndCallback(uint96 nonce, address scriptAddress, bytes calldata scriptCalldata)
        external
        payable
        returns (bytes memory)
    {
        // retrieve the (bucket, mask) pair that addresses the nonce in memory
        (uint256 bucket, uint256 setMask) = getBucket(nonce);

        // ensure nonce is not already set
        if (isNonceSetInternal(msg.sender, bucket, setMask)) {
            revert NonceAlreadySet();
        }

        // spend the nonce; only if the callee chooses to clear it will it get un-set and become replayable
        setNonceInternal(bucket, setMask);

        // if the nonce has been used before, check if the script address matches, and revert if not
        if (
            (nonceScriptAddress[msg.sender][nonce] != address(0))
                && (nonceScriptAddress[msg.sender][nonce] != scriptAddress)
        ) {
            revert NonceScriptMismatch();
        }

        // set the nonce-script pair active and yield to the wallet callback
        NonceScript memory previousNonceScript = activeNonceScript[msg.sender];
        activeNonceScript[msg.sender] = NonceScript({nonce: nonce, scriptAddress: scriptAddress});

        bytes memory result =
            IExecutor(msg.sender).executeScriptWithNonceLock{value: msg.value}(scriptAddress, scriptCalldata);

        // if a nonce was cleared, set the nonceScriptAddress to lock nonce re-use to the same script address
        if (nonceScriptAddress[msg.sender][nonce] == address(0) && !isNonceSetInternal(msg.sender, bucket, setMask)) {
            nonceScriptAddress[msg.sender][nonce] = scriptAddress;
        }

        // release the nonce when the wallet finishes executing callback
        activeNonceScript[msg.sender] = previousNonceScript;

        // otherwise, return the result.
        return result;
    }

    /// @notice Write arbitrary bytes to storage namespaced by the currently active nonce; reverts if no nonce is currently active
    function write(bytes32 key, bytes32 value) external {
        if (activeNonceScript[msg.sender].scriptAddress == address(0)) {
            revert NoActiveNonce();
        }
        walletStorage[msg.sender][activeNonceScript[msg.sender].nonce][key] = value;
    }

    /**
     * @notice Read from storage namespaced by the currently active nonce; reverts if no nonce is currently active
     * @return Value at the nonce storage location, as bytes
     */
    function read(bytes32 key) external view returns (bytes32) {
        if (activeNonceScript[msg.sender].scriptAddress == address(0)) {
            revert NoActiveNonce();
        }
        return walletStorage[msg.sender][activeNonceScript[msg.sender].nonce][key];
    }
}
