// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";

import "../../src/CodeJar.sol";
import "../../src/QuarkWallet.sol";

import "./../lib/Counter.sol";
import "./../lib/MaxCounterScript.sol";
import "./../lib/YulHelper.sol";
import "./../lib/Reverts.sol";
import "./../../src/core_scripts/CompoundLeverLoop.sol";
import "./../../src/interfaces/CometInterface.sol";
import "./../../src/interfaces/IERC20NonStandard.sol";

contract CompoundLeverLoopTest is Test {
    event Ping(uint256);

    CodeJar public codeJar;
    Counter public counter;

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));
    }

    function testCompoundLeverLoop() public {
        bytes memory cll = new YulHelper().getDeployed("CompoundLeverLoop.sol/CompoundLeverLoop.json");
        // TODO: Check who emitted.
        address account = address(0xb0b);
        address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address Comet = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
        
        deal(account, 1000e18);
        deal(WETH, account, 1000e18);
        deal(USDC, account, 1000e6);

        // lever(address cometAddress, uint256 targetLeverageRatio, address targetAsset, uint256 baseInputAmount)
        QuarkWallet wallet = new QuarkWallet{salt: 0}(account, codeJar);

        // SupplyTo wallet Comound
        vm.startPrank(account);
        IERC20NonStandard(WETH).approve(Comet, type(uint256).max);
        IERC20NonStandard(USDC).approve(Comet, type(uint256).max);
        CometInterface(Comet).supplyTo(address(wallet), WETH, 10e18);
        vm.stopPrank();
        vm.startPrank(address(wallet));
        IERC20NonStandard(WETH).approve(Comet, type(uint256).max);
        IERC20NonStandard(USDC).approve(Comet, type(uint256).max);
        vm.stopPrank();

        // wallet.executeQuarkOperation(
        //     cll,
        //     abi.encodeWithSelector(
        //     CompoundLeverLoop.lever.selector, 
        //     Comet,
        //     200, 
        //     WETH, 
        //     0 )
        // );
        // wallet.executeQuarkOperation(
        //     cll, 
        //     abi.encodeWithSelector(
        //         CompoundLeverLoop.leverLoop.selector,
        //         Comet, 
        //         1000e6, 
        //         WETH, 
        //         USDC
        //     )
        // );

        console.log("Comet position after:");
        console.log(CometInterface(Comet).collateralBalanceOf(address(wallet), WETH));
        console.log(CometInterface(Comet).borrowBalanceOf(address(wallet)));
    }
}
