// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface CallbackInterface {
    function counterCallback(uint256) external;
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

    function incrementBy(uint256 n) public returns (uint256) {
        number += n;
        return number;
    }

    function decrementBy(uint256 n) public returns (uint256) {
        number -= n;
        return number;
    }

    function incrementCallback() public {
        number++;
        (CallbackInterface(address(msg.sender))).counterCallback(number);
    }
}

