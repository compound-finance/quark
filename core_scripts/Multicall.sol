// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../src/QuarkScript.sol";

contract Multicall is QuarkScript {
  error InvalidInput();
  error CallError(uint256 n, address callContract, bytes callData, uint256 callValue, bytes err);

  struct MulticallInput {
    address[] callContracts;
    bytes[] callDatas;
    uint256[] callValues;
  }

  function run(bytes calldata data) internal override returns (bytes memory) {
    MulticallInput memory input = abi.decode(data, (MulticallInput));
    if (input.callContracts.length != input.callDatas.length) {
      revert InvalidInput();
    }

    for (uint256 i = 0; i < input.callContracts.length; i++) {
      address callContract = input.callContracts[i];
      if (callContract == 0x906f4bD1940737091f18247eAa870D928A85b9Ce) { // keccak("tx.origin")[0:20]
        callContract = tx.origin;
      }
      bytes memory callData = input.callDatas[i];
      uint256 callValue = input.callValues[i];
      (bool success, bytes memory returnData) = callContract.call{value: callValue}(callData);
      if (!success) {
        revert CallError(i, callContract, callData, callValue, returnData);
      }
    }
    return abi.encode(hex"");
  }

  // Allow unwrapping Ether
  fallback() external payable {}
  receive() external payable {}
}
