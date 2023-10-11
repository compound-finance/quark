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
    
    function incrementBy(uint256 n) public {
        number += n;
    }

    function decrementBy(uint256 n) public {
        number -= n;
    }

    function incrementAndCallback() public returns (bytes memory) {
        number++;
        (bool success, bytes memory result) = msg.sender.call("");
        if (!success) {
            assembly {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
        return result;
    }
}

