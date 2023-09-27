// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../QuarkScript.sol";

contract Ethcall is QuarkScript {
  error CallError(address callContract, bytes callData, uint256 callValue, bytes err);

  function run(address callContract, bytes calldata callData, uint256 callValue) external onlyRelayer returns (bytes memory) {
    address callAddress = callContract;
    if (callContract == 0x906f4bD1940737091f18247eAa870D928A85b9Ce) { // keccak("tx.origin")[0:20]
      callAddress = tx.origin;
    }
    (bool success, bytes memory returnData) = callAddress.call{value: callValue}(callData);
    if (!success) {
      revert CallError(callContract, callData, callValue, returnData);
    } else {
      return returnData;
    }
  }

  // Allow unwrapping Ether
  receive() external payable {}
}
