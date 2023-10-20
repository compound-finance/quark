// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract Logger {
    event Ping(uint256);

    fallback() external {
        emit Ping(55);
    }
}
