// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdMath.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";

import {QuarkWalletProxyFactory} from "quark-proxy/src/QuarkWalletProxyFactory.sol";

import {Counter} from "test/lib/Counter.sol";

import {YulHelper} from "test/lib/YulHelper.sol";
import {SignatureHelper} from "test/lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "test/lib/QuarkOperationHelper.sol";

import "legend-scripts/src/LegendScript.sol";

/**
 * Tests for repaying and withdrawing multiple assets from Comet
 */
contract CometRepayAndWithdrawMultipleAssetsTest is Test {
    QuarkWalletProxyFactory public factory;
    Counter public counter;
    uint256 alicePrivateKey = 0xa11ce;
    address alice = vm.addr(alicePrivateKey);

    // Contracts address on mainnet
    address constant comet = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;

    function setUp() public {
        // Fork setup
        vm.createSelectFork(
            string.concat(
                "https://node-provider.compound.finance/ethereum-mainnet/", vm.envString("NODE_PROVIDER_BYPASS_KEY")
            ),
            18429607 // 2023-10-25 13:24:00 PST
        );
        factory = new QuarkWalletProxyFactory(address(new QuarkWallet(new CodeJar(), new QuarkStateManager())));
    }

    function testRepayAndWithdrawMultipleAssets() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));
        bytes memory legendScript =
            new YulHelper().getDeployed("LegendScript.sol/CometRepayAndWithdrawMultipleAssets.json");

        deal(WETH, address(wallet), 10 ether);
        deal(LINK, address(wallet), 10e18);
        vm.startPrank(address(wallet));
        IERC20(WETH).approve(comet, 10 ether);
        IERC20(LINK).approve(comet, 10e18);
        IComet(comet).supply(WETH, 10 ether);
        IComet(comet).supply(LINK, 10e18);
        IComet(comet).withdraw(USDC, 100e6);
        vm.stopPrank();

        address[] memory assets = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        assets[0] = WETH;
        assets[1] = LINK;
        amounts[0] = 10 ether;
        amounts[1] = 10e18;
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            legendScript,
            abi.encodeCall(CometRepayAndWithdrawMultipleAssets.run, (comet, assets, amounts, USDC, 100e6)),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 0);
        assertEq(IERC20(LINK).balanceOf(address(wallet)), 0);
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 100e6);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 10 ether);
        assertEq(IERC20(LINK).balanceOf(address(wallet)), 10e18);
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 0);
    }

    function testInvalidInput() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));
        bytes memory legendScript =
            new YulHelper().getDeployed("LegendScript.sol/CometRepayAndWithdrawMultipleAssets.json");

        address[] memory assets = new address[](2);
        uint256[] memory amounts = new uint256[](1);
        assets[0] = WETH;
        assets[1] = LINK;
        amounts[0] = 10 ether;

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            legendScript,
            abi.encodeCall(CometRepayAndWithdrawMultipleAssets.run, (comet, assets, amounts, USDC, 100e6)),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        vm.expectRevert(abi.encodeWithSelector(TerminalErrors.InvalidInput.selector));
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
    }
}
