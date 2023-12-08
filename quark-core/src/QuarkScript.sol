// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "quark-core/src/QuarkWallet.sol";

/**
 * @title Quark Script
 * @notice A contract that exposes helper functions for Quark scripts to inherit from
 * @author Compound Labs, Inc.
 */
abstract contract QuarkScript {
    error ReentrantCall();

    /// @notice storage location for the re-entrancy guard
    bytes32 internal constant REENTRANCY_FLAG = keccak256("quark.scripts.reentrancy.guard.v1");

    modifier nonReentrant() {
        if (read(REENTRANCY_FLAG) == bytes32(uint256(1))) {
            revert ReentrantCall();
        }
        write(REENTRANCY_FLAG, bytes32(uint256(1)));

        _;

        write(REENTRANCY_FLAG, bytes32(uint256(0)));
    }

    function signer() internal view returns (address) {
        (, bytes memory signer_) = address(this).staticcall(abi.encodeWithSignature("signer()"));
        return abi.decode(signer_, (address));
    }

    function executor() internal view returns (address) {
        (, bytes memory executor_) = address(this).staticcall(abi.encodeWithSignature("executor()"));
        return abi.decode(executor_, (address));
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
