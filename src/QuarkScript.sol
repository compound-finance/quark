// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "./QuarkWallet.sol";

contract QuarkScript {
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
