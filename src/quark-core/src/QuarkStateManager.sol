// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";

/**
 * @title Quark State Manager
 * @notice Contract for managing nonces for Quark wallets
 * @author Compound Labs, Inc.
 */
contract QuarkStateManager {
    error NonceAlreadySet();
    error NoUnusedNonces();

    /// @notice Bit-packed nonce values
    mapping(address wallet => mapping(uint256 bucket => uint256 bitset)) public nonces;

    /**
     * @notice Return whether a nonce has been exhausted
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
     * @notice Returns the next valid unset nonce for a given wallet
     * @dev Any unset nonce is valid to use, but using this method
     * increases the likelihood that the nonce you use will be in a bucket that
     * has already been written to, which costs less gas
     * @param wallet Address of the wallet to find the next nonce for
     * @return The next unused nonce
     */
    function nextNonce(address wallet) external view returns (uint96) {
        // Any bucket larger than `type(uint88).max` will result in unsafe undercast when converting to nonce
        for (uint256 bucket = 0; bucket <= type(uint88).max; ++bucket) {
            uint96 bucketValue = uint96(bucket << 8);
            uint256 bucketNonces = nonces[wallet][bucket];
            // Move on to the next bucket if all bits in this bucket are already set
            if (bucketNonces == type(uint256).max) continue;
            for (uint256 maskOffset = 0; maskOffset < 256; ++maskOffset) {
                uint256 mask = 1 << maskOffset;
                if ((bucketNonces & mask) == 0) {
                    uint96 nonce = uint96(bucketValue + maskOffset);
                    return nonce;
                }
            }
        }

        revert NoUnusedNonces();
    }

    /// @dev Locate a nonce at a (bucket, mask) bitset position in the nonces mapping
    function getBucket(uint96 nonce) internal pure returns (uint256, /* bucket */ uint256 /* mask */ ) {
        uint256 bucket = nonce >> 8;
        uint256 setMask = 1 << (nonce & 0xff);
        return (bucket, setMask);
    }

    /**
     * @notice Set a given nonce for the calling wallet, reverting if the nonce is already set
     * @param nonce Nonce to set for the calling wallet
     */
    function setNonce(uint96 nonce) external {
        (uint256 bucket, uint256 setMask) = getBucket(nonce);
        if (isNonceSetInternal(msg.sender, bucket, setMask)) {
            revert NonceAlreadySet();
        }
        setNonceInternal(bucket, setMask);
    }

    /// @dev Set a nonce for the msg.sender, using the nonce's bucket and mask
    function setNonceInternal(uint256 bucket, uint256 setMask) internal {
        nonces[msg.sender][bucket] |= setMask;
    }
}
