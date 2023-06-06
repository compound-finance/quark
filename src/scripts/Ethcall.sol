// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../QuarkScript.sol";

contract Ethcall is QuarkScript {
  error CallError(address wrappedContract, bytes wrappedCalldata, bytes err);

  struct EthcallInput {
    address wrappedContract,
    bytes wrappedCalldata,
  }

  function run(bytes calldata data) internal override returns (bytes memory) {
    EthcallInput memory input = abi.decode(data, EthcallInput);

    (bool success, bytes memory returnData) = input.wrappedContract.call(input.wrappedCalldata);
    if (!success) {
      revert CallError(input.wrappedContract, input.wrappedCalldata, returnData);
    } else {
      return returnData;
    }
  }
}
