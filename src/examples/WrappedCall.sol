// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../QuarkScript.sol";

interface IErc20 {
  function transfer(address to, uint256 amount) external returns (bool);
}

contract WrappedCall is QuarkScript {
  error WrappedCallError(address wrappedContract, bytes wrappedCalldata, bytes err);

  function run(bytes calldata data) internal override returns (bytes memory) {
    (IErc20 payToken, uint256 amount, address wrappedContract, bytes memory wrappedCalldata) = abi.decode(data, (IErc20, uint256, address, bytes));

    payToken.transfer(tx.origin, amount);
    (bool success, bytes memory returnData) = wrappedContract.call(wrappedCalldata);
    if (!success) {
      revert WrappedCallError(wrappedContract, wrappedCalldata, returnData);
    } else {
      return returnData;
    }
  }
}
