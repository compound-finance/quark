// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract QuarkStorageManager {
    error InvalidNonce(uint256);
    error NoNonceAcquired();
    error NoUnusedNonces();

    /// @notice Bit-packed nonce values
    mapping(address /* wallet */ => mapping(uint256 /* bucket */ => uint256 /* bitset */)) public nonces;

    /// @notice Nonce acquired by a wallet, if any, to execute a script using that nonce
    mapping(address /* wallet */ => uint256 /* nonce */) internal acquiredNonce;

    /// @notice Per-wallet-nonce storage space that can be utilized while a nonce is acquired
    mapping(address /* wallet */ => mapping(uint256 /* nonce */ => mapping(bytes32 /* key */ => bytes32 /* storage */)))
        internal nonceKVs;

    /**
     * @notice Return whether a nonce has been exhausted; note that if a nonce is not set, that does not mean it has not been used before
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
     * @notice Return the nonce currently acquired by a wallet; revert if none
     * @return Currently acquired nonce
     */
    function getAcquiredNonce() external view returns (uint256) {
        if (acquiredNonce[msg.sender] == 0) {
            revert NoNonceAcquired();
        }
        return acquiredNonce[msg.sender];
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
     * @notice Un-spend the acquired nonce to allow its reuse; intended for replayable transactions
     */
    function unsetNonce() external {
        if (acquiredNonce[msg.sender] == 0) {
            revert NoNonceAcquired();
        }
        (uint256 bucket, uint256 setMask) = locateNonce(acquiredNonce[msg.sender]);
        nonces[msg.sender][bucket] &= ~setMask;
    }

    /**
     * @notice Acquire a wallet nonce and yield control back to the wallet by calling into yieldTarget
     * @param nonce Nonce to acquire for the transaction
     * @dev The wallet is expected to setNonce(..) when the nonce has been exhausted; acquiring a nonce does not necessarily exhaust it
     */
    function acquireNonceAndYield(uint256 nonce, bytes calldata yieldTarget) external returns (bytes memory) {
        if (nonce == 0) {
            revert InvalidNonce(nonce);
        }

        // acquire the nonce and yield to the wallet yieldTarget
        uint256 acquiredParent = acquiredNonce[msg.sender];
        acquiredNonce[msg.sender] = nonce;

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
        // otherwise, release the nonce when the wallet finishes executing yieldTarget, and return the result of the call
        acquiredNonce[msg.sender] = acquiredParent;
        // currently, result is double-encoded. un-encode it.
        return abi.decode(result, (bytes));
    }

    /**
     * @notice Write arbitrary bytes to storage namespaced by the currently acquired nonce; reverts if no nonce is currently acquired
     */
    function write(bytes32 key, bytes32 value) external {
        if (acquiredNonce[msg.sender] == 0) {
            revert NoNonceAcquired();
        }
        nonceKVs[msg.sender][acquiredNonce[msg.sender]][key] = value;
    }

    /**
     * @notice Read from storage namespaced by the currently acquired nonce; reverts if no nonce is currently acquired
     * @return Value at the nonce storage location, as bytes
     */
    function read(bytes32 key) external returns (bytes32) {
        if (acquiredNonce[msg.sender] == 0) {
            revert NoNonceAcquired();
        }
        return nonceKVs[msg.sender][acquiredNonce[msg.sender]][key];
    }
}
