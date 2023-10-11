// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract Counter {
    uint256 public number;

    function setNumber(uint256 newNumber) public {
        number = newNumber;
    }

    function increment() public {
        number++;
    }

    function increment(uint256 n) public {
        number += n;
    }

    function incrementAndCallback() public returns (bytes memory) {
        number++;
        (bool success, bytes memory result) = msg.sender.call("");
        if (!success) {
            assembly {
                let size := mload(result)
                revert(add(result, 0x20), size)
            }
        }
        return result;
    }
}

