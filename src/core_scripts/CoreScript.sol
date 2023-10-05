// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../QuarkScript.sol";

contract CoreScript is QuarkScript{
  error InvalidInput();
  error CallError(address callContract, bytes callData, uint256 callValue, bytes err);
  error MultiCallError(uint256 n, address callContract, bytes callData, uint256 callValue, bytes err);
  error DelegateCallError(bytes callCode, bytes callData, uint256 callValue, bytes err);
  error MultiDelegateCallError(uint256 n, bytes callCode, bytes callData, uint256 callValue, bytes err);

  function executeMultiInternal(address[] memory callContracts, bytes[] memory callDatas, uint256[] memory callValues) internal {
    if (callContracts.length != callDatas.length || callContracts.length != callValues.length) {
        revert InvalidInput();
    }

    for (uint256 i = 0; i < callContracts.length; i++) {
        (bool success, bytes memory returnData) = callContracts[i].call{value: callValues[i]}(callDatas[i]);
        if (!success) {
          revert MultiCallError(i, callContracts[i], callDatas[i], callValues[i], returnData);
        }
    }
  }

  function executeSingleInternal(address callContract, bytes memory callData, uint256 callValue) internal returns (bytes memory) {
    (bool success, bytes memory returnData) = callContract.call{value: callValue}(callData);
      if (!success) {
        revert CallError(callContract, callData, callValue, returnData);
      }
      return returnData;
  }

  // Allow unwrapping Ether
  receive() external payable {}
}