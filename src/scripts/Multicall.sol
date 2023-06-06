// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../QuarkScript.sol";

contract Multicall is QuarkScript {
  error InvalidInput();
  error CallError(uint256 n, address wrappedContract, bytes wrappedCalldata, bytes err);

  struct MulticallInput {
    address[] wrappedContracts;
    bytes[] wrappedCalldatas;
  }

  function run(bytes calldata data) internal override returns (bytes memory) {
    MulticallInput memory input = abi.decode(data, (MulticallInput));
    if (input.wrappedContracts.length != input.wrappedCalldatas.length) {
      revert InvalidInput();
    }

    for (uint256 i = 0; i < input.wrappedContracts.length; i++) {
      address wrappedContract = input.wrappedContracts[i];
      bytes memory wrappedCalldata = input.wrappedCalldatas[i];
      (bool success, bytes memory returnData) = wrappedContract.call(wrappedCalldata);
      if (!success) {
        revert CallError(i, wrappedContract, wrappedCalldata, returnData);
      }
    }
    return abi.encode(hex"");
  }
}
