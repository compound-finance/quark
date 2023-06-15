// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../src/QuarkScript.sol";

contract Ethcall is QuarkScript {
  error CallError(address callContract, bytes callData, uint256 callValue, bytes err);

  struct EthcallInput {
    address callContract;
    bytes callData;
    uint256 callValue;
  }

  function run(bytes calldata data) internal override returns (bytes memory) {
    EthcallInput memory input = abi.decode(data, (EthcallInput));

    address callAddress = input.callContract;
    if (input.callContract == 0x906f4bD1940737091f18247eAa870D928A85b9Ce) { // keccak("tx.origin")[0:20]
      callAddress = tx.origin;
    }
    (bool success, bytes memory returnData) = callAddress.call{value: input.callValue}(input.callData);
    if (!success) {
      revert CallError(input.callContract, input.callData, input.callValue, returnData);
    } else {
      return returnData;
    }
  }

  // Allow unwrapping Ether
  fallback() external payable {}
  receive() external payable {}
}
