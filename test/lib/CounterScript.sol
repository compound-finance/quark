// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import "test/lib/Counter.sol";

contract CounterScript {
    function run(Counter c) external returns (bytes memory) {
        c.increment();
        c.increment();
        return hex"";
    }
}
