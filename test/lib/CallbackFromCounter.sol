// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "./Counter.sol";
import "../../src/QuarkScript.sol";

contract CallbackFromCounter is QuarkScript {
    function doIncrementAndCallback(Counter counter) public payable {
        allowCallback();
        counter.incrementAndCallback{value: msg.value}();
    }

    function callback() external payable {
        Counter counter = Counter(msg.sender);
        counter.increment(counter.number() * 10);
    }
}
