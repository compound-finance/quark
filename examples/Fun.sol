// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract Fun {
  event FunTimes(uint256);

  function hello() external {
    emit FunTimes(55);
  }
}


