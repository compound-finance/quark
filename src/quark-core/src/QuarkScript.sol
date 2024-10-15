// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import {QuarkWallet, QuarkWalletMetadata, IHasSignerExecutor, IQuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkNonceManager, QuarkNonceManagerMetadata} from "quark-core/src/QuarkNonceManager.sol";

/**
 * @title Quark Script
 * @notice A contract that exposes helper functions for Quark scripts to inherit from
 * @author Compound Labs, Inc.
 */
abstract contract QuarkScript {
    error ReentrantCall();
    error InvalidActiveNonce();
    error InvalidActiveSubmissionToken();

    /// @notice Transient storage location for the re-entrancy guard
    bytes32 internal constant REENTRANCY_FLAG_SLOT =
        bytes32(uint256(keccak256("quark.scripts.reentrancy.guard.v1")) - 1);

    /// @notice Reentrancy guard that writes the flag to the wallet's transient storage
    modifier nonReentrant() {
        bytes32 slot = REENTRANCY_FLAG_SLOT;
        bytes32 flag;
        assembly {
            flag := tload(slot)
        }
        if (flag == bytes32(uint256(1))) {
            revert ReentrantCall();
        }
        assembly {
            tstore(slot, 1)
        }

        _;

        assembly {
            tstore(slot, 0)
        }
    }

    /**
     * @notice A cheaper, but weaker reentrancy guard that does not prevent recursive reentrancy (e.g. script calling itself)
     * @dev Use with caution; this guard should only be used if the function being guarded cannot recursively call itself
     *      There are currently two ways to do this from a script:
     *         1. The script uses `delegatecall` and the target can be itself (technically the wallet). The script
     *            has to also enable callbacks for this reentrancy to succeed.
     *         2. The script defines circular codepaths that can be used to reenter the function using internal
     *            functions.
     * @dev A side-effect of using this guard is that the guarded function can no longer be called as part of the Quark wallet
     *      callback flow. This is because the fallback in Quark wallet makes a `delegatecall` instead of a `callcode`. The
     *      guarded function would still be able to be called if a calling contract calls into the Quark wallet fallback using
     *      a `delegatecall`, but most calling contracts are likely to make a `call` into the Quark wallet fallback instead.
     */
    modifier onlyWallet() {
        if (msg.sender != address(this)) {
            revert ReentrantCall();
        }

        _;
    }

    /// @notice Returns the `signer` of the wallet
    function signer() internal view returns (address) {
        return IHasSignerExecutor(address(this)).signer();
    }

    /// @notice Returns the `executor` of the wallet
    function executor() internal view returns (address) {
        return IHasSignerExecutor(address(this)).executor();
    }

    /// @notice Returns the `NonceManager` of the wallet
    function nonceManager() internal view returns (QuarkNonceManager) {
        return QuarkNonceManager(IQuarkWallet(address(this)).nonceManager());
    }

    /// @notice Enables callbacks to the wallet
    function allowCallback() internal {
        bytes32 callbackSlot = QuarkWalletMetadata.CALLBACK_SLOT;
        bytes32 activeScriptSlot = QuarkWalletMetadata.ACTIVE_SCRIPT_SLOT;
        assembly {
            let activeScript := tload(activeScriptSlot)
            tstore(callbackSlot, activeScript)
        }
    }

    /// @notice Disables callbacks to the wallet
    function clearCallback() internal {
        bytes32 callbackSlot = QuarkWalletMetadata.CALLBACK_SLOT;
        assembly {
            tstore(callbackSlot, 0)
        }
    }

    /**
     * @notice Reads a uint256 from the wallet's storage
     * @param key The key to read the value from
     * @return The uint256 stored at the key
     */
    function readU256(string memory key) internal view returns (uint256) {
        return uint256(read(key));
    }

    /**
     * @notice Reads a bytes32 from the wallet's storage
     * @param key The key to read the value from
     * @return The bytes32 stored at the key
     */
    function read(string memory key) internal view returns (bytes32) {
        return read(keccak256(bytes(key)));
    }

    /**
     * @notice Reads a bytes32 from the wallet's storage
     * @param key The key to read the value from
     * @return The bytes32 stored at the key
     */
    function read(bytes32 key) internal view returns (bytes32) {
        bytes32 value;
        bytes32 isolatedKey = getNonceIsolatedKey(key);
        assembly {
            value := sload(isolatedKey)
        }
        return value;
    }

    /**
     * @notice Writes a uint256 to the wallet's storage
     * @param key The key to write the value to
     * @param value The value to write to storage
     */
    function writeU256(string memory key, uint256 value) internal {
        return write(key, bytes32(value));
    }

    /**
     * @notice Writes a bytes32 to the wallet's storage
     * @param key The key to write the value to
     * @param value The value to write to storage
     */
    function write(string memory key, bytes32 value) internal {
        return write(keccak256(bytes(key)), value);
    }

    /**
     * @notice Writes a bytes32 to the wallet's storage
     * @param key The key to write the value to
     * @param value The value to write to storage
     */
    function write(bytes32 key, bytes32 value) internal {
        bytes32 isolatedKey = getNonceIsolatedKey(key);
        assembly {
            sstore(isolatedKey, value)
        }
    }

    /**
     * @notice Returns a key isolated to the active nonce of a script. This provides cooperative isolation of storage between scripts.
     * @param key The key to create an nonce-isolated version of
     */
    function getNonceIsolatedKey(bytes32 key) internal view returns (bytes32) {
        bytes32 nonce = getActiveNonce();
        return keccak256(abi.encodePacked(nonce, key));
    }

    /// @notice Returns the active nonce of the wallet
    function getActiveNonce() internal view returns (bytes32) {
        bytes32 activeNonceSlot = QuarkWalletMetadata.ACTIVE_NONCE_SLOT;
        bytes32 value;
        assembly {
            value := tload(activeNonceSlot)
        }

        return value;
    }

    /// @notice Returns the active submission token of the wallet
    function getActiveSubmissionToken() internal view returns (bytes32) {
        bytes32 activeSubmissionTokenSlot = QuarkWalletMetadata.ACTIVE_SUBMISSION_TOKEN_SLOT;
        bytes32 value;
        assembly {
            value := tload(activeSubmissionTokenSlot)
        }
        return value;
    }

    /**
     * @notice Returns the active replay count of this script. Thus, the first submission should return 0,
     *         the second submission 1, and so on.
     * @param key The key to create an nonce-isolated version of
     */
    function getActiveReplayCount() internal view returns (uint256) {
        bytes32 nonce = getActiveNonce();
        bytes32 submissionToken = getActiveSubmissionToken();
        uint256 n;

        if (submissionToken == QuarkNonceManagerMetadata.EXHAUSTED) {
            return 0;
        }

        for (n = 0; submissionToken != nonce; n++) {
            submissionToken = keccak256(abi.encodePacked(submissionToken));
        }

        return n;
    }
}
