// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdMath.sol";

import "./../../src/QuarkWallet.sol";
import "./../../src/QuarkWalletFactory.sol";
import "./../../src/terminal_scripts/TerminalScript.sol";
import "./../lib/YulHelper.sol";
import "./../lib/SignatureHelper.sol";
import "./../lib/Counter.sol";
import "./../lib/QuarkOperationHelper.sol";

/**
 * Scenario test for user borrow base asset from Comet v3 market
 */
contract WithdrawActionsTest is Test {
    QuarkWalletFactory public factory;
    Counter public counter;
    uint256 alicePrivateKey = 0xa11ce;
    address alice = vm.addr(alicePrivateKey);

    // Contracts address on mainnet
    address constant comet = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    bytes terminalScript = new YulHelper().getDeployed(
            "TerminalScript.sol/CometWithdrawActions.json"
        );

    function setUp() public {
        // Fork setup
        vm.createSelectFork(
            string.concat(
                "https://node-provider.compound.finance/ethereum-mainnet/", vm.envString("NODE_PROVIDER_BYPASS_KEY")
            ),
            18429607 // 2023-10-25 13:24:00 PST
        );
        factory = new QuarkWalletFactory();
    }

    function testWithdraw() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        deal(WETH, address(wallet), 10 ether);

        vm.startPrank(address(wallet));
        IERC20(WETH).approve(comet, 10 ether);
        IComet(comet).supply(WETH, 10 ether);
        vm.stopPrank();

        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 10 ether);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 0 ether);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            terminalScript,
            abi.encodeWithSelector(CometWithdrawActions.withdraw.selector, comet, WETH, 10 ether),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 0 ether);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 10 ether);
    }

    function testWithdrawTo() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        QuarkWallet wallet2 = QuarkWallet(factory.create(alice, bytes32("1")));
        deal(WETH, address(wallet), 10 ether);

        vm.startPrank(address(wallet));
        IERC20(WETH).approve(comet, 10 ether);
        IComet(comet).supply(WETH, 10 ether);
        vm.stopPrank();

        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 10 ether);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 0 ether);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            terminalScript,
            abi.encodeWithSelector(CometWithdrawActions.withdrawTo.selector, comet, address(wallet2), WETH, 10 ether),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 0 ether);
        assertEq(IERC20(WETH).balanceOf(address(wallet2)), 10 ether);
    }

    function testWithdrawFrom() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        QuarkWallet wallet2 = QuarkWallet(factory.create(alice, bytes32("1")));
        deal(WETH, address(wallet2), 10 ether);

        vm.startPrank(address(wallet2));
        IERC20(WETH).approve(comet, 10 ether);
        IComet(comet).supply(WETH, 10 ether);
        IComet(comet).allow(address(wallet), true);
        vm.stopPrank();

        assertEq(IComet(comet).collateralBalanceOf(address(wallet2), WETH), 10 ether);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 0 ether);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            terminalScript,
            abi.encodeWithSelector(CometWithdrawActions.withdrawFrom.selector, comet, address(wallet2), address(wallet), WETH, 10 ether),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(IComet(comet).collateralBalanceOf(address(wallet2), WETH), 0 ether);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 10 ether);
    }

    function testBorrow() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        deal(WETH, address(wallet), 10 ether);

        vm.startPrank(address(wallet));
        IERC20(WETH).approve(comet, 10 ether);
        IComet(comet).supply(WETH, 10 ether);
        vm.stopPrank();

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            terminalScript,
            abi.encodeWithSelector(CometWithdrawActions.withdraw.selector, comet, USDC, 100e6),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(IERC20(USDC).balanceOf(address(wallet)), 100e6);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 0 ether);
        assertEq(IComet(comet).borrowBalanceOf(address(wallet)), 100e6);
        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 10 ether);
    }

    function testWithdrawMultipleAssets() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));

        deal(WETH, address(wallet), 10 ether);
        deal(LINK, address(wallet), 1000e18);
        deal(USDC, address(wallet), 1000e6);

        vm.startPrank(address(wallet));
        IERC20(WETH).approve(comet, 10 ether);
        IComet(comet).supply(WETH, 10 ether);
        IERC20(LINK).approve(comet, 1000e18);
        IComet(comet).supply(LINK, 1000e18);
        IERC20(USDC).approve(comet, 1000e6);
        IComet(comet).supply(USDC, 1000e6);
        vm.stopPrank();

        address[] memory assets = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        assets[0] = WETH;
        assets[1] = LINK;
        assets[2] = USDC;
        amounts[0] = 10 ether;
        amounts[1] = 1000e18;
        amounts[2] = 1000e6;

        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 10 ether);
        assertEq(IComet(comet).collateralBalanceOf(address(wallet), LINK), 1000e18);
        assertApproxEqAbs(IComet(comet).balanceOf(address(wallet)), 1000e6, 1); // Comet math issue (lost 1 wei after deposit)
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 0 ether);
        assertEq(IERC20(LINK).balanceOf(address(wallet)), 0e18);
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 0e6);
        // Fastforward 180 days
        vm.roll(185529607);
        vm.warp(block.timestamp + 180 days);
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            terminalScript,
             abi.encodeWithSelector(
                CometWithdrawActions.withdrawMultipleAssets.selector, comet, assets, amounts
                ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 0 ether);
        assertEq(IComet(comet).collateralBalanceOf(address(wallet), LINK), 0e18);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 10 ether);
        assertEq(IERC20(LINK).balanceOf(address(wallet)), 1000e18);
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 1000e6);
    }
}
