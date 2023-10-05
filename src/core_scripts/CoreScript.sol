// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../CodeJar.sol";
import "../QuarkScript.sol";

contract CoreScript is QuarkScript{
  error InvalidInput();
  error CallError(address callContract, bytes callData, uint256 callValue, bytes err);
  error MultiCallError(uint256 n, address callContract, bytes callData, uint256 callValue, bytes err);
  error DelegateCallError(bytes callCode, bytes callData, uint256 callValue, bytes err);
  error MultiDelegateCallError(uint256 n, bytes callCode, bytes callData, uint256 callValue, bytes err);

  function executeMultiInternal(address[] memory callContracts, bytes[] memory callCodes, bytes[] memory callDatas, uint256[] memory callValues) internal returns (bytes memory) {
    if (callContracts.length != callDatas.length || callContracts.length != callCodes.length || callContracts.length != callValues.length) {
        revert InvalidInput();
    }

    for (uint256 i = 0; i < callContracts.length; i++) {
      bool isCallContract = callContracts[i] != address(0);
      bool isCallCode = callCodes[i].length != 0;
      if (isCallCode == isCallContract) {
        revert InvalidInput();
      }

      if (isCallCode) {
        if(callValues[i] != 0) {
          revert InvalidInput();
        }

        address codeAddress = relayer().codeJar().saveCode(callCodes[i]);
        (bool success, bytes memory returnData) = codeAddress.delegatecall(callDatas[i]);
        if (!success) {
          revert MultiDelegateCallError(i, callCodes[i], callDatas[i], callValues[i], returnData);
        }
      } else if (isCallContract) {
        (bool success, bytes memory returnData) = callContracts[i].call{value: callValues[i]}(callDatas[i]);
        if (!success) {
          revert MultiCallError(i, callContracts[i], callDatas[i], callValues[i], returnData);
        }
      } else {
        revert InvalidInput();
      }
    }
    return abi.encode(hex"");
  }

  function executeSingleInternal(address callContract, bytes memory callCode, bytes memory callData, uint256 callValue) internal returns (bytes memory) {
    bool isCallContract = callContract != address(0);
    bool isCallCode = callCode.length != 0;
    if (isCallCode == isCallContract) {
      revert InvalidInput();
    }

    if (isCallCode) {
      if (callValue != 0) {
        revert InvalidInput();
      }
      
      address codeAddress = relayer().codeJar().saveCode(callCode);
      (bool success, bytes memory returnData) = codeAddress.delegatecall(callData);
      if (!success) {
        revert DelegateCallError(callCode, callData, callValue, returnData);
      }
      
      return returnData;
    } else if (isCallContract) {
      (bool success, bytes memory returnData) = callContract.call{value: callValue}(callData);
      if (!success) {
        revert CallError(callContract, callData, callValue, returnData);
      }

      return returnData;
    } else {
      revert InvalidInput();
    }
  }

  // Allow unwrapping Ether
  receive() external payable {}
}