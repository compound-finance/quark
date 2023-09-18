// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../src/QuarkScript.sol";
import "./Counter.sol";

contract MaxCounterScript is QuarkScript {
  error EnoughAlready();

  string constant maxCountVar = "quark.org.MaxCounterScript.maxCount";

  function run(Counter c) external onlyRelayer returns (bytes memory) {
    c.increment();
    uint256 count = sloadU256(maxCountVar);
    if (count >= 3) {
      revert EnoughAlready();
    }

    sstoreU256(maxCountVar, count + 1);
    return hex"";
  }
}

