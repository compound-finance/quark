// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import {QuarkWallet, IHasSignerExecutor} from "quark-core/src/QuarkWallet.sol";

/**
 * @title Quark Script
 * @notice A contract that exposes helper functions for Quark scripts to inherit from
 * @author Compound Labs, Inc.
 */
abstract contract QuarkScript {
    error ReentrantCall();
    error InvalidActiveNonce();
    error InvalidActiveSubmissionToken();

    /// @notice Storage location for the re-entrancy guard
    bytes32 internal constant REENTRANCY_FLAG_SLOT =
        bytes32(uint256(keccak256("quark.scripts.reentrancy.guard.v1")) - 1);

    /// @notice A safer, but gassier reentrancy guard that writes the flag to the QuarkNonceManager
    modifier nonReentrant() {
        bytes32 slot = REENTRANCY_FLAG_SLOT;
        bytes32 flag;
        // TODO: Move to TSTORE after updating Solidity version to >=0.8.24
        assembly {
            flag := sload(slot)
        }
        if (flag == bytes32(uint256(1))) {
            revert ReentrantCall();
        }
        assembly {
            sstore(slot, 1)
        }

        _;

        assembly {
            sstore(slot, 0)
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

    function signer() internal view returns (address) {
        return IHasSignerExecutor(address(this)).signer();
    }

    function executor() internal view returns (address) {
        return IHasSignerExecutor(address(this)).executor();
    }

    function allowCallback() internal {
        QuarkWallet self = QuarkWallet(payable(address(this)));
        // TODO: Can save gas by just having the constant in QuarkScript
        bytes32 callbackSlot = self.CALLBACK_SLOT();
        bytes32 activeScriptSlot = self.ACTIVE_SCRIPT_SLOT();
        assembly {
            // TODO: Move to TLOAD/TSTORE after updating Solidity version to >=0.8.24
            let activeScript := sload(activeScriptSlot)
            sstore(callbackSlot, activeScript)
        }
    }

    function clearCallback() internal {
        QuarkWallet self = QuarkWallet(payable(address(this)));
        bytes32 callbackSlot = self.CALLBACK_SLOT();
        assembly {
            // TODO: Move to TSTORE after updating Solidity version to >=0.8.24
            sstore(callbackSlot, 0)
        }
    }

    function readU256(string memory key) internal view returns (uint256) {
        return uint256(read(key));
    }

    function read(string memory key) internal view returns (bytes32) {
        return read(keccak256(bytes(key)));
    }

    function read(bytes32 key) internal view returns (bytes32) {
        bytes32 value;
        assembly {
            value := sload(key)
        }
        return value;
    }

    function writeU256(string memory key, uint256 value) internal {
        return write(key, bytes32(value));
    }

    function write(string memory key, bytes32 value) internal {
        return write(keccak256(bytes(key)), value);
    }

    // TODO: Consider adding nonce-based scoping by TLOAD'ing the nonce and using
    // that to hash the key.
    function write(bytes32 key, bytes32 value) internal {
        assembly {
            sstore(key, value)
        }
    }

    // Note: this may not be accurate after any nested calls from a script
    function getActiveNonce() internal returns (bytes32) {
        QuarkWallet self = QuarkWallet(payable(address(this)));

        bytes32 activeNonceSlot = self.ACTIVE_NONCE_SLOT();
        bytes32 value;
        assembly {
            value := sload(activeNonceSlot)
        }
        if (value == bytes32(0)) {
            revert InvalidActiveNonce();
        }

        return value;
    }

    // Note: this may not be accurate after any nested calls from a script
    function getActiveSubmissionToken() internal returns (bytes32) {
        QuarkWallet self = QuarkWallet(payable(address(this)));

        bytes32 activeSubmissionTokenSlot = self.ACTIVE_SUBMISSION_TOKEN_SLOT();
        bytes32 value;
        assembly {
            value := sload(activeSubmissionTokenSlot)
        }
        if (value == bytes32(0)) {
            revert InvalidActiveSubmissionToken();
        }
        return value;
    }

    // Note: this may not be accurate after any nested calls from a script
    // Returns the active replay count of this script. Thus, the first submission should return 0,
    // the second submission 1, and so on. This must be called before the script makes any external calls.
    function getActiveReplayCount() internal returns (uint256) {
        bytes32 nonce = getActiveNonce();
        bytes32 submissionToken = getActiveSubmissionToken();
        uint256 n;

        if (submissionToken == bytes32(type(uint256).max)) {
            return 0;
        }

        for (n = 0; submissionToken != nonce; n++) {
            submissionToken = keccak256(abi.encodePacked(submissionToken));
        }

        return n;
    }
}
