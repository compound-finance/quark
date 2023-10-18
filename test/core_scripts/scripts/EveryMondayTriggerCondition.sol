// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../../src/QuarkScript.sol";

contract EveryMondayTriggerCondition is QuarkScript {
    // Offset days from 1970-01-01 which was from Thursday
    uint256 public constant MONDAY_OFFSET = 4;
    mapping(address => uint256) public lastRunTimestamp;

    error ConditionFailed();
    error NotMonday();

    function timeToWeeklyRun() external {
        // Days after 1970-01-01 week
        uint256 currentDayOfWeek = block.timestamp % 1 weeks / 1 days;
        if (currentDayOfWeek != MONDAY_OFFSET) {
            revert NotMonday();
        }
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
