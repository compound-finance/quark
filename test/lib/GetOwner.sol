// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../src/QuarkScript.sol";

contract GetOwner is QuarkScript {
  fallback(bytes calldata data) external payable returns (bytes memory) {
    return abi.encode(owner());
  }
}