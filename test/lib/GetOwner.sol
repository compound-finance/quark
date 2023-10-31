// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "../../src/QuarkScript.sol";
import "../../src/QuarkWallet.sol";

contract GetOwner is QuarkScript {
    function getOwner() external returns (address) {
        return QuarkWallet(payable(address(this))).owner();
    }
}
