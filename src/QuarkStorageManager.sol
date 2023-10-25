// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

contract QuarkStorageManager {
    error InvalidNonce(uint256);
    error NoNonceActive();
    error NoUnusedNonces();

    /// @notice Bit-packed nonce values
    mapping(address /* wallet */ => mapping(uint256 /* bucket */ => uint256 /* bitset */)) public nonces;

    /// @notice Currently active nonce for a wallet, if any, for which storage is accessible
    mapping(address /* wallet */ => uint256 /* nonce */) internal activeNonce;

    /// @notice Per-wallet-nonce storage space that can be utilized while a nonce is active
    mapping(address /* wallet */ => mapping(uint256 /* nonce */ => mapping(bytes32 /* key */ => bytes32 /* storage */)))
        internal nonceKVs;

    /**
     * @notice Return whether a nonce has been exhausted; note that if a nonce is not set, that does not mean it has not been used before
     * @dev `0` is not a valid nonce
     * @param wallet Address of the wallet owning the nonce
     * @param nonce Nonce to check
     * @return Whether the nonce has been exhausted
     */
    function isNonceSet(address wallet, uint256 nonce) public view returns (bool) {
        if (nonce == 0) {
            revert InvalidNonce(nonce);
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
    function nextUnusedNonce(address wallet) external view returns (uint256) {
        uint256 i;
        for (i = 1; i < type(uint256).max; i++) {
            if (!isNonceSet(wallet, i)) return i;
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
     * @dev Locate a nonce at a (bucket, mask) bitset position in the public nonces mapping
     */
    function locateNonce(uint256 nonce) internal pure returns (uint256 /* bucket */, uint256 /* nonce */) {
        if (nonce == 0) {
            revert InvalidNonce(nonce);
        }
        uint256 bucket = nonce >> 8;
        uint256 setMask = 1 << (nonce & 0xff);
        return (bucket, setMask);
    }

    /**
     * @notice Un-spend the active nonce to allow its reuse; intended for replayable transactions
     */
    function unsetNonce() external {
        if (activeNonce[msg.sender] == 0) {
            revert NoNonceActive();
        }
        (uint256 bucket, uint256 setMask) = locateNonce(activeNonce[msg.sender]);
        nonces[msg.sender][bucket] &= ~setMask;
    }

    /**
     * @notice Set a wallet nonce as the active nonce and yield control back to the wallet by calling into yieldTarget
     * @param nonce Nonce to activate for the transaction
     * @dev The wallet is expected to setNonce(..) when the nonce has been exhausted; activating a nonce does not necessarily exhaust it
     */
    function setActiveNonceAndYield(uint256 nonce, bytes calldata yieldTarget) external returns (bytes memory) {
        if (nonce == 0) {
            revert InvalidNonce(nonce);
        }

        // set the nonce active and yield to the wallet yieldTarget
        uint256 parentActiveNonce = activeNonce[msg.sender];
        activeNonce[msg.sender] = nonce;

        // spend the nonce; only if the callee chooses to save it will it get un-set and become replayable
        (uint256 bucket, uint256 setMask) = locateNonce(nonce);
        nonces[msg.sender][bucket] |= setMask;

        (bool success, bytes memory result) = msg.sender.call(yieldTarget);
        // if the call fails, propagate the revert from the wallet
        if (!success) {
            assembly {
                revert(add(result, 0x20), mload(result))
            }
        }

        // release the nonce when the wallet finishes executing yieldTarget
        activeNonce[msg.sender] = parentActiveNonce;

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
        nonceKVs[msg.sender][activeNonce[msg.sender]][key] = value;
    }

    /**
     * @notice Read from storage namespaced by the currently active nonce; reverts if no nonce is currently active
     * @return Value at the nonce storage location, as bytes
     */
    function read(bytes32 key) external returns (bytes32) {
        if (activeNonce[msg.sender] == 0) {
            revert NoNonceActive();
        }
        return nonceKVs[msg.sender][activeNonce[msg.sender]][key];
    }
}
