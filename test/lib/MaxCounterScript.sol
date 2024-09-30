// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import "quark-core/src/QuarkScript.sol";
import "test/lib/Counter.sol";

contract MaxCounterScript is QuarkScript {
    error EnoughAlready();

    event Count(uint256 c);

    function run(Counter c) external returns (bytes memory) {
        c.increment();
        uint256 count = readU256("count");

        if (count >= 3) {
            revert EnoughAlready();
        }

        writeU256("count", count + 1);
        emit Count(count + 1);

        return hex"";
    }
}
