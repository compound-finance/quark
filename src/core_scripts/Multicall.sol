// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./CoreScript.sol";

contract Multicall is CoreScript {
  function run(address[] calldata callContracts, bytes[] calldata callCodes, bytes[] calldata callDatas, uint256[] calldata callValues) external returns (bytes memory) {
    return executeMultiInternal(callContracts, callCodes, callDatas, callValues);
  }
}