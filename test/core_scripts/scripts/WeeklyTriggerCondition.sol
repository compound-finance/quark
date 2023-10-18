// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../../src/QuarkScript.sol";

contract WeeklyTriggerCondition is QuarkScript {
    mapping(address => uint256) public lastRunTimestamp;

    error ConditionFailed();

    function timeToWeeklyRun() external {
        if (lastRunTimestamp[msg.sender] == 0) {
            lastRunTimestamp[msg.sender] = block.timestamp;
        } else {
            if (block.timestamp - lastRunTimestamp[msg.sender] >= 7 days) {
                lastRunTimestamp[msg.sender] = block.timestamp;
            } else {
                revert ConditionFailed();
            }
        }
    }
}
