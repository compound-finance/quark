// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "test/lib/Counter.sol";
import "quark-core/src/QuarkScript.sol";

contract CallbackFromCounter is QuarkScript {
    function doIncrementAndCallback(Counter counter) public {
        allowCallback();
        counter.incrementAndCallback();
    }

    function doIncrementAndCallbackWithFee(Counter counter, uint256 fee) public {
        allowCallback();
        counter.incrementAndCallbackWithFee(fee);
    }

    function callback() external payable {
        Counter counter = Counter(msg.sender);
        counter.increment(counter.number() * 10);
    }
}
