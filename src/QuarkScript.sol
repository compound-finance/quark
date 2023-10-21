// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

contract QuarkScript {
    function owner() internal view returns (address payable) {
        address payable owner_;
        assembly {
            owner_ := sload(0x3bb5ebf00f3b539fbe3d28370e5631dd2bb9520dffcea6daf564f94582db8111) // keccak("org.quark.owner")
        }
        return owner_;
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
