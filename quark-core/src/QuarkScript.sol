// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {QuarkWallet, HasSignerExecutor} from "quark-core/src/QuarkWallet.sol";

/**
 * @title Quark Script
 * @notice A contract that exposes helper functions for Quark scripts to inherit from
 * @author Compound Labs, Inc.
 */
abstract contract QuarkScript {
    error ReentrantCall();

    /// @notice Storage location for the re-entrancy guard
    bytes32 internal constant REENTRANCY_FLAG_SLOT = bytes32(uint256(keccak256("quark.scripts.reentrancy.guard.v1")) - 1);

    /// @notice A safer, but gassier reentrancy guard that writes the flag to the QuarkStateManager
    modifier nonReentrant() {
        if (read(REENTRANCY_FLAG_SLOT) == bytes32(uint256(1))) {
            revert ReentrantCall();
        }
        write(REENTRANCY_FLAG_SLOT, bytes32(uint256(1)));

        _;

        write(REENTRANCY_FLAG_SLOT, bytes32(uint256(0)));
    }

    /**
     * @notice A gas optimized reentrancy guard that writes to the wallet's storage instead of the QuarkStateManager
     * @dev Note: Use with caution; make sure that the slot is not overwritten by other scripts
     */
    modifier nonReentrantOptimized() {
        bytes32 slot = REENTRANCY_FLAG_SLOT;
        uint256 status;
        assembly ("memory-safe") {
            status := sload(slot)
        }

        if (status != 0) revert ReentrantCall();
        assembly ("memory-safe") {
            sstore(slot, 1)
        }

        _;

        assembly ("memory-safe") {
            sstore(slot, 0)
        }
    }

    /**
     * @notice A cheaper, but weaker reentrancy guard that does not prevent recursive reentrancy (e.g. script calling itself)
     * @dev Use with caution; this guard should only be used if the function being guarded cannot recursively call itself
     *      There are currently two ways to do this from a script:
     *         1. The script uses `delegatecall` and the target can be itself (technically the wallet). The script
     *            script has to also enable callbacks for this reentrancy to succeed.
     *         2. The script defines circular codepaths that can be used to reenter the function using internal
     *            functions.
     */
    modifier onlyWallet() {
        if (msg.sender != address(this)) {
            revert ReentrantCall();
        }

        _;
    }

    function signer() internal view returns (address) {
        return HasSignerExecutor(address(this)).signer();
    }

    function executor() internal view returns (address) {
        return HasSignerExecutor(address(this)).executor();
    }

    function allowCallback() internal {
        QuarkWallet self = QuarkWallet(payable(address(this)));
        self.stateManager().write(self.CALLBACK_KEY(), bytes32(uint256(uint160(self.stateManager().getActiveScript()))));
    }

    function allowReplay() internal {
        return QuarkWallet(payable(address(this))).stateManager().clearNonce();
    }

    function readU256(string memory key) internal view returns (uint256) {
        return uint256(read(key));
    }

    function read(string memory key) internal view returns (bytes32) {
        return read(keccak256(bytes(key)));
    }

    function read(bytes32 key) internal view returns (bytes32) {
        return QuarkWallet(payable(address(this))).stateManager().read(key);
    }

    function writeU256(string memory key, uint256 value) internal {
        return write(key, bytes32(value));
    }

    function write(string memory key, bytes32 value) internal {
        return write(keccak256(bytes(key)), value);
    }

    function write(bytes32 key, bytes32 value) internal {
        return QuarkWallet(payable(address(this))).stateManager().write(key, value);
    }
}
