// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IErc20 {
  function transfer(address to, uint256 amount) external returns (bool);
}

contract PayLog {
  event Hello(uint256 n);

  function payLog(IErc20 payToken, uint256 amount, uint256 n) public {
    payToken.transfer(tx.origin, amount);
    emit Hello(n);
  }
}
