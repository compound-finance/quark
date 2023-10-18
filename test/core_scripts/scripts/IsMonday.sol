// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract IsMonday {
    // Offset days from 1970-01-01 which was from Thursday
    uint256 public constant MONDAY_OFFSET = 4;

    function isMonday() external view returns (bool) {
        // Days after 1970-01-01 week
        uint256 currentDayOfWeek = block.timestamp % 1 weeks / 1 days;
        if (currentDayOfWeek != MONDAY_OFFSET) {
            return false;
        } else {
            return true;
        }
    }
}
