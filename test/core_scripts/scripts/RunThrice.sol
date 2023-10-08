// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../../src/QuarkScript.sol";

contract RunThrice is QuarkScript {
    error EnoughAlready(uint256 max);

    string constant countVar = "quark.org.RunThrice.count";

    function runCheck(uint256 max) external {
        uint256 count = sloadU256(countVar);
        if (count >= max) {
          revert EnoughAlready(max);
        }

        sstoreU256(countVar, count + 1);
    }
}