// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "../../../src/QuarkScript.sol";
import "./../interfaces/IComet.sol";

contract SupplyComet is QuarkScript {
    function supply(address comet, address asset, uint256 amount) external {
        IComet(comet).supplyFrom(msg.sender, msg.sender, asset, amount);
    }

    function supplyAndBorrow(address comet, address asset, uint256 amount, address borrowAsset, uint256 borrowAmount)
        external
    {
        IComet(comet).supplyFrom(msg.sender, msg.sender, asset, amount);
        IComet(comet).withdrawFrom(msg.sender, msg.sender, borrowAsset, borrowAmount);
    }
}
