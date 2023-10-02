// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract Reverts {
  error Whoops();

  fallback() external {
    revert Whoops();
  }
}
