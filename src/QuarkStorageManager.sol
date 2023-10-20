// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract QuarkStorageManager {
    /// @notice Bit-packed nonce values
    mapping(address /* wallet */ => mapping(uint256 /* bucket */ => uint256 /* bitset */)) public nonces;

    /// @notice Nonce acquired by a wallet, if any, to execute a script using that nonce
    mapping(address /* wallet */ => /* nonce */ uint256) internal acquiredNonce;

    /// @notice Per-wallet-nonce storage space that can be utilized while a nonce is acquired
    mapping(address /* wallet */ => mapping(uint256 /* nonce */ => bytes /* storage */)) internal namespacedStorage;

    /// @notice Per-wallet-nonce proxy target that the wallet may choose to call in its fallback function, e.g. for callbacks
    mapping(address /* wallet */ => mapping(uint256 /* nonce */ => address /* target */)) internal proxyTarget;

    /**
     * @notice Return whether a nonce has been exhausted; note that if a nonce is not set, that does not mean it has not been used before
     * @param wallet Address of the wallet owning the nonce
     * @param nonce Nonce to check
     * @return Whether the nonce has been exhausted
     */
    function isNonceSet(address wallet, uint256 nonce) public view returns (bool) {
        uint256 bucket = nonce >> 8;
        uint256 mask = 1 << (nonce & 0xff);
        return nonces[wallet][bucket] & mask != 0;
    }

    /**
     * @notice Return the nonce currently acquired by a wallet; revert if none
     * @param wallet Address of the wallet owning the nonce
     * @return Currently acquired nonce
     */
    function getAcquiredNonce(address wallet) external view returns (uint256) {
        if (acquiredNonce[wallet] == 0) {
            revert(); // XXX
        }
        return acquiredNonce[wallet];
    }

    /**
     * @notice Set a given wallet nonce as exhausted; this method is only available to the wallet, and when a nonce is acquired, no other nonce can be set until it is released
     * @param wallet Address of the wallet owning the nonce
     * @param nonce Nonce to set
     */
    function setNonce(address wallet, uint256 nonce) external {
        if (msg.sender != wallet) {
            revert(); // XXX only the wallet is allowed to set its own nonces
            // QUESTION: allow the owner EOA to set nonces? e.g. to unbork the wallet if nonces are messed up somehow
        }
        if (acquiredNonce[wallet] != 0 && acquiredNonce[wallet] != nonce) {
            revert(); // XXX only the currently acquired nonce can be set, if a nonce is currently acquired
        }
        uint256 bucket = nonce >> 8;
        uint256 mask = 1 << (nonce & 0xff);
        nonces[wallet][bucket] |= mask;
    }

    /**
     * @notice Returns the next unset nonce for a given wallet
     * @dev Any unset nonce is valid to use, but using this method increases
     * the likelihood that the nonce you use will be on a bucket that has
     * already been written to, which costs less gas
     * @return The next unused nonce
     */
    function nextUnusedNonce(address wallet) external view returns (uint256) {
        uint256 i;
        for (i = 1; i < type(uint256).max; i++) {
            if (!isNonceSet(wallet, i)) return i;
        }
        revert(); // XXX NoUnusedNonces
    }

    /**
     * @notice Acquire a wallet nonce and yield control back to the wallet by calling into yieldTarget
     * @param nonce Nonce to acquire for the transaction
     * @dev The wallet is expected to setNonce(..) when the nonce has been exhausted; acquiring a nonce does not necessarily exhaust it
     */
    function acquireNonceAndYield(address wallet, uint256 nonce, bytes calldata yieldTarget) external returns (bytes memory) {
        if (msg.sender != wallet) {
            revert(); // XXX only the wallet can acquire a nonce
        }
        // check whether nonce can be acquired
        if (acquiredNonce[wallet] != 0) {
            revert(); // XXX there is already a nonce acquired
        }
        if (isNonceSet(wallet, nonce)) {
            revert(); // XXX the desired nonce is already set
        }
        if (nonce == 0) {
            revert(); // XXX nonce=0 is invalid
        }
        // acquire the nonce and yield to the wallet yieldTarget
        acquiredNonce[wallet] = nonce;
        (bool success, bytes memory result) = wallet.call(yieldTarget);
        // if the call fails, propagate the revert from the wallet
        if (!success) {
            assembly {
                revert(add(result, 0x20), mload(result))
            }
        }
        // otherwise, release the nonce when the wallet finishes executing yieldTarget, and return the result of the call
        acquiredNonce[wallet] = 0;
        // currently, result is double-encoded. un-encode it.
        return abi.decode(result, (bytes));
    }

    /**
     * @notice Get the proxy target for the currently acquired nonce, an address the wallet may choose to call in its fallback function
     * @param wallet Address of the wallet
     * @return Address of the proxy target contract, which may be the null address
     */
    function getProxyTarget(address wallet) external returns (address) {
        if (msg.sender != wallet) {
            revert(); // XXX only the wallet can see its proxy target
        }
        if (acquiredNonce[wallet] == 0) {
            revert(); // XXX the proxy target can only be read for an acquired nonce
        }
        return proxyTarget[wallet][acquiredNonce[wallet]];
    }

    /**
     * @notice Set the proxy target for the currently acquired nonce, an address the wallet may choose to call in its fallback function
     * @param wallet Address of the wallet
     * @param target Address of the proxy target contract
     */
    function setProxyTarget(address wallet, address target) external {
        if (msg.sender != wallet) {
            revert(); // XXX only the wallet can set its proxy target
        }
        if (acquiredNonce[wallet] == 0) {
            revert(); // XXX the proxy target can only be set for an acquired nonce
        }
        proxyTarget[wallet][acquiredNonce[wallet]] = target;
    }

    /**
     * @notice Write arbitrary bytes to storage namespaced by the currently acquired nonce; reverts if no nonce is currently acquired
     * @param wallet Address of the wallet owning the nonce
     */
    function write(address wallet, bytes calldata value) external {
        if (acquiredNonce[wallet] == 0) {
            revert(); // XXX storage at a given nonce can only be accessed while the nonce is acquired
        }
        namespacedStorage[wallet][acquiredNonce[wallet]] = value;
    }

    /**
     * @notice Read from storage namespaced by the currently acquired nonce; reverts if no nonce is currently acquired
     * @param wallet Address of the wallet owning the nonce
     * @return Value at the nonce storage location, as bytes
     */
    function read(address wallet) external returns (bytes memory) {
        if (acquiredNonce[wallet] == 0) {
            revert(); // XXX storage at a given nonce can only be accessed while the nonce is acquired
        }
        return namespacedStorage[wallet][acquiredNonce[wallet]];
    }
}
