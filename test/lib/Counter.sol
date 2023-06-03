// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

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

    function incrementCallback() public {
        number++;
        (CallbackInterface(address(msg.sender))).counterCallback(number);
    }
}
