// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Counter.sol";

contract CounterScript {
    function run(Counter c) external returns (bytes memory) {
        c.increment();
        c.increment();
        return hex"";
    }
}
