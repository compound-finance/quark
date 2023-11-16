// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.21;

interface HasCallback {
    function callback() external payable;
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

    function decrement(uint256 n) public returns (uint256) {
        number -= n;
        return number;
    }

    function incrementAndCallback() public payable {
        number++;
        return HasCallback(msg.sender).callback{value: msg.value}();
    }
}
