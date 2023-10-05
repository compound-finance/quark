// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../QuarkScript.sol";
import "../interfaces/IComet.sol";
import "../interfaces/IERC20.sol";

contract CometSupply is QuarkScript {
  function run(CometSupplyAction memory action) public {
    ERC20(action.asset).approve(action.comet, action.amount);
    IComet(action.comet).supply(action.asset, action.amount);
  }
}

struct CometSupplyAction {
  address comet;
  address asset;
  uint256 amount;
}
