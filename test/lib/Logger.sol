// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.21;

contract Logger {
    event Ping(uint256);

    fallback() external {
        emit Ping(55);
    }
}
