// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Relayer.sol";

contract QuarkScript {
    function owner() internal view returns (address payable) {
        address payable owner_;
        assembly {
            owner_ := sload(0x3bb5ebf00f3b539fbe3d28370e5631dd2bb9520dffcea6daf564f94582db8111) // keccak("org.quark.owner")
        }
        return owner_;
    }

    function relayer() internal view returns (Relayer) {
        Relayer relayer_;
        assembly {
            relayer_ := sload(0x46ce4d9fc828e2af4f167362c7c43e310c76adc313cd8fe11e785726f972b4f6) // keccak("org.quark.relayer")
        }
        return relayer_;
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

    modifier onlyRelayer() {
        require(msg.sender == address(relayer()));
        _;
    }
}
