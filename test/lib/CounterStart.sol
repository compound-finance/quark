// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Counter.sol";

contract CounterStart is Counter {
    constructor (uint256 start) {
        assembly {
            log2(0, 0, 0xDEADBEA7, start)
        }
        setNumber(start);
    }
}
