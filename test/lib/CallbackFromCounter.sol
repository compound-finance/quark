// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/console.sol";

import "./Counter.sol";
import "../../src/QuarkScript.sol";

contract CallbackFromCounter is QuarkScript {
    function doIncrementAndCallback(Counter counter) public {
        allowCallback();
        counter.incrementAndCallback();
    }

    function callback() external {
        Counter counter = Counter(msg.sender);
        counter.increment(counter.number() * 10);
    }
}
