// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./CoreScript.sol";

contract Ethcall is CoreScript {  
  function run(address callContract, bytes calldata callData, uint256 callValue) external returns (bytes memory) {
    return executeSingleInternal(callContract, callData, callValue);
  }
}