// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../../src/QuarkScript.sol";
import "../../../src/core_scripts/interfaces/IComet.sol";

contract SupplyComet is QuarkScript {
    function supply(address comet, address asset, uint256 amount) external {
        IComet(comet).supply(asset, amount);
    }
}