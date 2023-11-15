// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

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
