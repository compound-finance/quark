// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract QuarkStorageManager {
    /// @notice Bit-packed nonce values
    mapping(address /* wallet */ => mapping(uint256 /* bucket */ => uint256 /* bitset */)) public nonces;

    /// @notice Nonce acquired by a wallet, if any, to execute a script using that nonce
    mapping(address /* wallet */ => uint256 /* nonce */) internal acquiredNonce;

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
        if (nonce == 0) {
            revert("invalid nonce=0"); // XXX nonce=0 is invalid
        }
        uint256 bucket = nonce >> 8;
        uint256 mask = 1 << (nonce & 0xff);
        return nonces[wallet][bucket] & mask != 0;
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
     * @notice Return the nonce currently acquired by a wallet; revert if none
     * @return Currently acquired nonce
     */
    function getAcquiredNonce() external view returns (uint256) {
        if (acquiredNonce[msg.sender] == 0) {
            revert("not acquired"); // XXX
        }
        return acquiredNonce[msg.sender];
    }

    /**
     * @notice Set the acquired nonce to either "spent" or "free".
     */
    function setNonce(bool isSpent /* gross */) internal {
        // spend the nonce; it may be un-spent (?) by the script in order to allow replayability
        if (acquiredNonce[msg.sender] == 0) {
            revert("not acquired"); // XXX
        }
        uint256 nonce = acquiredNonce[msg.sender];
        uint256 bucket = nonce >> 8;
        uint256 setMask = (1 << (nonce & 0xff));
        if (isSpent) {
            nonces[msg.sender][bucket] |= setMask;
        } else {
            nonces[msg.sender][bucket] &= ~setMask;
        }
    }

    /**
     * @notice Un-spend the acquired nonce to allow its reuse; intended for replayable transactions
     */
    function unsetNonce() external {
        if (acquiredNonce[msg.sender] == 0) {
            revert("not acquired"); // XXX
        }
        setNonce(false);
    }

    /**
     * @notice Acquire a wallet nonce and yield control back to the wallet by calling into yieldTarget
     * @param nonce Nonce to acquire for the transaction
     * @dev The wallet is expected to setNonce(..) when the nonce has been exhausted; acquiring a nonce does not necessarily exhaust it
     */
    function acquireNonceAndYield(uint256 nonce, bytes calldata yieldTarget) external returns (bytes memory) {
        if (nonce == 0) {
            revert("invalid nonce=0"); // XXX nonce=0 is invalid
        }
        // acquire the nonce and yield to the wallet yieldTarget
        uint256 acquiredParent = acquiredNonce[msg.sender];
        acquiredNonce[msg.sender] = nonce;
        // spend the nonce; only if the callee chooses to save it will it get un-set and become replayable
        setNonce(true);
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
     * @notice Get the proxy target for the currently acquired nonce, an address the wallet may choose to call in its fallback function
     * @return Address of the proxy target contract, which may be the null address
     */
    function getProxyTarget() external returns (address) {
        if (acquiredNonce[msg.sender] == 0) {
            revert(); // XXX the proxy target can only be read for an acquired nonce
        }
        return proxyTarget[msg.sender][acquiredNonce[msg.sender]];
    }

    /**
     * @notice Set the proxy target for the currently acquired nonce, an address the wallet may choose to call in its fallback function
     * @param target Address of the proxy target contract
     */
    function setProxyTarget(address target) external {
        if (acquiredNonce[msg.sender] == 0) {
            revert("not acquired"); // XXX the proxy target can only be set for an acquired nonce
        }
        proxyTarget[msg.sender][acquiredNonce[msg.sender]] = target;
    }

    /**
     * @notice Write arbitrary bytes to storage namespaced by the currently acquired nonce; reverts if no nonce is currently acquired
     */
    function write(bytes calldata value) external {
        if (acquiredNonce[msg.sender] == 0) {
            revert(); // XXX storage at a given nonce can only be accessed while the nonce is acquired
        }
        namespacedStorage[msg.sender][acquiredNonce[msg.sender]] = value;
    }

    /**
     * @notice Read from storage namespaced by the currently acquired nonce; reverts if no nonce is currently acquired
     * @return Value at the nonce storage location, as bytes
     */
    function read() external returns (bytes memory) {
        if (acquiredNonce[msg.sender] == 0) {
            revert(); // XXX storage at a given nonce can only be accessed while the nonce is acquired
        }
        return namespacedStorage[msg.sender][acquiredNonce[msg.sender]];
    }
}
