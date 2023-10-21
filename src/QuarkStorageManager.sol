// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract QuarkStorageManager {
    /// @notice Bit-packed nonce values
    mapping(address /* wallet */ => mapping(uint256 /* bucket */ => uint256 /* bitset */)) public nonces;

    /// @notice Nonce acquired by a wallet, if any, to execute a script using that nonce
    mapping(address /* wallet */ => /* nonce */ uint256) internal activeNonce;

    /// @notice Per-wallet-nonce storage space that can be utilized while a nonce is acquired
    mapping(address /* wallet */ => mapping(uint256 /* nonce */ => mapping(bytes32 /* key */ => bytes /* storage */))) internal data;

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
    function getActiveNonce(address wallet) public view returns (uint256) {
        if (activeNonce[wallet] == 0) {
            revert(); // XXX
        }
        return activeNonce[wallet];
    }

    /**
     * @notice Set a given wallet nonce as exhausted; this method is only available to the wallet, and when a nonce is acquired, no other nonce can be set until it is released
     */
    function setNonce() public {
        uint256 nonce = activeNonce[msg.sender];
        if (nonce == 0) {
            revert("not acquired"); // XXX only the currently acquired nonce can be set, if a nonce is currently acquired
        }
        uint256 bucket = nonce >> 8;
        uint256 mask = 1 << (nonce & 0xff);
        nonces[msg.sender][bucket] |= mask;
    }

    /**
     * @notice Acquire a wallet nonce and yield control back to the wallet by calling into yieldTarget
     * @param nonce Nonce to acquire for the transaction
     * @dev The wallet is expected to setNonce(..) when the nonce has been exhausted; acquiring a nonce does not necessarily exhaust it
     */
    function setActiveNonce(uint256 nonce, bool doSetNonce, bytes calldata callbackData) external returns (bytes memory) {
        if (nonce == 0) {
            revert("invalid nonce=0"); // XXX nonce=0 is invalid
        }
        if (isNonceSet(msg.sender, nonce)) {
            revert("already set"); // XXX the desired nonce is already set
        }
        if (activeNonce[msg.sender] != 0){
            revert("active already");
        }
        activeNonce[msg.sender] = nonce;
        if (doSetNonce) {
            setNonce();
        }
        (bool success, bytes memory result) = msg.sender.call(callbackData);
        // if the call fails, propagate the revert from the wallet
        if (!success) {
            assembly {
                revert(add(result, 0x20), mload(result))
            }
        }
        // otherwise, release the nonce when the wallet finishes executing yieldTarget, and return the result of the call
        activeNonce[msg.sender] = 0;
        // currently, result is double-encoded. un-encode it.
        return abi.decode(result, (bytes));
    }

    /**
     * @notice Write arbitrary bytes to storage namespaced by the currently acquired nonce; reverts if no nonce is currently acquired
     */
    function write(bytes32 key, bytes calldata value) external {
        if (activeNonce[msg.sender] == 0) {
            revert(); // XXX storage at a given nonce can only be accessed while the nonce is acquired
        }
        data[msg.sender][activeNonce[msg.sender]][key] = value;
    }

    /**
     * @notice Read from storage namespaced by the currently acquired nonce; reverts if no nonce is currently acquired
     * @return Value at the nonce storage location, as bytes
     */
    function read(bytes32 key) external returns (bytes memory) {
        if (activeNonce[msg.sender] == 0) {
            revert(); // XXX storage at a given nonce can only be accessed while the nonce is acquired
        }
        return data[msg.sender][activeNonce[msg.sender]][key];
    }
}
