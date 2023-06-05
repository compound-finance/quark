// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../src/QuarkScript.sol";

interface Erc20 {
  function transfer(address to, uint256 amount) external returns (bool);
}

contract PayScript is QuarkScript {
  event Hello(uint256 n);

  function run(bytes calldata data) internal override returns (bytes memory) {
    (Erc20 payToken, uint256 amount, uint256 n) = abi.decode(data, (Erc20, uint256, uint256));
    payToken.transfer(tx.origin, amount);
    emit Hello(n);
    return hex"";
  }
}
