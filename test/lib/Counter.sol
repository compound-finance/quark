// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface HasCallback {
    function callback() external;
}

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

    function incrementAndCallback() public {
        number++;
        return HasCallback(msg.sender).callback();
    }
}
