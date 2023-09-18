// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../src/QuarkScript.sol";
import "./Counter.sol";

contract CounterScript is QuarkScript {
  function run(Counter c) external onlyRelayer returns (bytes memory) {
    c.increment();
    c.increment();
    return hex"";
  }
}

