// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Counter.sol";

contract CounterStart is Counter {
    constructor () {
        uint256 start = abi.decode(msg.data, (uint256));
        setNumber(start);
    }
}
