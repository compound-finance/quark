// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

contract Reverts {
    error Whoops();

    fallback() external {
        revert Whoops();
    }
}
