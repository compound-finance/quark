// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/console.sol";

import "./Counter.sol";

contract CallbackFromCounter {
    function doIncrementAndCallback(Counter counter) external {
      counter.incrementAndCallback();
    }

    fallback() external {
      Counter counter = Counter(msg.sender);
      counter.increment(counter.number() * 10);
    }
}
