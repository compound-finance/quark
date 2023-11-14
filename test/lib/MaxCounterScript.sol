// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.21;

import "../../src/QuarkScript.sol";
import "./Counter.sol";

contract MaxCounterScript is QuarkScript {
    error EnoughAlready();

    function run(Counter c) external returns (bytes memory) {
        c.increment();
        uint256 count = readU256("count");

        if (count >= 3) {
            revert EnoughAlready();
        }

        writeU256("count", count + 1);
        allowReplay();

        return hex"";
    }
}
