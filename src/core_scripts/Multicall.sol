// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./CoreScript.sol";

contract Multicall is CoreScript {
  function run(address[] calldata callContracts, bytes[] calldata callDatas, uint256[] calldata callValues) external {
    executeMultiInternal(callContracts, callDatas, callValues);
  }
}