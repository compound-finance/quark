// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";

import "../../src/CodeJar.sol";
import "../../src/QuarkWallet.sol";

import "../../src/core/scripts/CometSupply.sol";

import "../lib/YulHelper.sol";

contract CometSupplyTest is Test {

    CodeJar codeJar;
    address comet = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));
    }

    function setUp() public {
        // no setup.
    }

    function testCometSupplySucceeds() public {
        address account = address(0xa11ce);
        QuarkWallet wallet = new QuarkWallet{salt: 0}(account, codeJar);

        bytes memory supplyScript = new YulHelper().getDeployed("CometSupply.sol/CometSupply.json");

        
        deal(usdc, address(wallet), 5000000);

        CometSupplyAction memory action = CometSupplyAction({
            comet: comet,
            asset: usdc,
            amount: 5000000 // 5 USDC
        });

        wallet.executeQuarkOperation(
            supplyScript,
            abi.encodeWithSelector(
                CometSupply.run.selector,
                action
            )
        );

        // assertEq(IComet(comet).balanceOf(address(wallet)), 5000000);
    }
}
