// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "./QuarkWallet.sol";

contract QuarkScript {
    function allowCallback() internal {
        QuarkWallet self = QuarkWallet(payable(address(this)));
        self.stateManager().write(self.CALLBACK_KEY(), bytes32(uint256(uint160(self.stateManager().getActiveScript()))));
    }

    function sloadU256(string memory key) internal view returns (uint256) {
        return uint256(sload(key));
    }

    function sload(string memory key) internal view returns (bytes32) {
        return sload(keccak256(bytes(key)));
    }

    function sload(bytes32 key) internal view returns (bytes32 res) {
        assembly {
            res := sload(key)
        }
    }

    function sstoreU256(string memory key, uint256 value) internal {
        return sstore(keccak256(bytes(key)), bytes32(value));
    }

    function sstore(bytes32 key, bytes32 value) internal {
        assembly {
            sstore(key, value)
        }
    }
}
