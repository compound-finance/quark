// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IErc20 {
  function transfer(address to, uint256 amount) external returns (bool);
}

contract WrappedCall {
  function exec(IErc20 payToken, uint256 amount, address wrappedContract, bytes calldata wrappedCalldata) external returns (bytes memory) {
    payToken.transfer(tx.origin, amount);
    (bool success, bytes memory returnData) = wrappedContract.call(wrappedCalldata);
    require(success);
    return returnData;
  }
}
