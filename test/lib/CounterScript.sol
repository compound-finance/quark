// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../src/QuarkScript.sol";
import "./Counter.sol";

contract CounterScript is QuarkScript {
  function run(bytes calldata data) internal override returns (bytes memory) {
    (Counter c) = abi.decode(data, (Counter));
    c.increment();
    c.increment();
  }
}
