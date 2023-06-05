// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Counter.sol";

contract CounterForm {
  function run(Counter c) external {
    c.increment();
    c.increment();
    c.increment();
    c.increment();
  }
}
