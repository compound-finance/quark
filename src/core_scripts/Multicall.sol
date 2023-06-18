// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../QuarkScript.sol";

contract Multicall is QuarkScript {
  error InvalidInput();
  error CallError(uint256 n, address callContract, bytes callData, uint256 callValue, bytes err);

  function run(address[] calldata callContracts, bytes[] calldata callDatas, uint256[] calldata callValues) external onlyRelayer returns (bytes memory) {
    if (callContracts.length != callDatas.length) {
      revert InvalidInput();
    }

    for (uint256 i = 0; i < callContracts.length; i++) {
      address callContract = callContracts[i];
      if (callContract == 0x906f4bD1940737091f18247eAa870D928A85b9Ce) { // keccak("tx.origin")[0:20]
        callContract = tx.origin;
      }
      bytes memory callData = callDatas[i];
      uint256 callValue = callValues[i];
      (bool success, bytes memory returnData) = callContract.call{value: callValue}(callData);
      if (!success) {
        revert CallError(i, callContract, callData, callValue, returnData);
      }
    }
    return abi.encode(hex"");
  }

  // Allow unwrapping Ether
  receive() external payable {}
}
