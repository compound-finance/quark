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
contract SupplyActionsTest is Test {
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
            "TerminalScript.sol/CometSupplyActions.json"
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

    function testSupply() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));

        deal(WETH, address(wallet), 10 ether);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            terminalScript,
            abi.encodeWithSelector(CometSupplyActions.supply.selector, comet, WETH, 10 ether),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 10 ether);
        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 0 ether);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 0 ether);
        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 10 ether);
    }

    function testSupplyTo() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        QuarkWallet wallet1 = QuarkWallet(factory.create(alice, bytes32("1")));

        deal(WETH, address(wallet), 10 ether);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            terminalScript,
            abi.encodeWithSelector(CometSupplyActions.supplyTo.selector, comet, address(wallet1), WETH, 10 ether),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 10 ether);
        assertEq(IComet(comet).collateralBalanceOf(address(wallet1), WETH), 0 ether);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 0 ether);
        assertEq(IComet(comet).collateralBalanceOf(address(wallet1), WETH), 10 ether);
    }

    function testSupplyFrom() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        QuarkWallet wallet1 = QuarkWallet(factory.create(alice, bytes32("1")));

        deal(WETH, address(wallet1), 10 ether);
        vm.startPrank(address(wallet1));
        IERC20(WETH).approve(comet, 10 ether);
        IComet(comet).allow(address(wallet), true);
        vm.stopPrank();

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            terminalScript,
            abi.encodeWithSelector(CometSupplyActions.supplyFrom.selector, comet, address(wallet1), address(wallet), WETH, 10 ether),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        assertEq(IERC20(WETH).balanceOf(address(wallet1)), 10 ether);
        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 0 ether);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 0 ether);
        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 10 ether);
    }

    function testSupplyCollateralAsset() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));

        deal(WETH, address(wallet), 10 ether);
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            terminalScript,
            abi.encodeWithSelector(CometSupplyActions.supply.selector, comet, WETH, 10 ether),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 10 ether);
        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 0 ether);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 0 ether);
        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 10 ether);
    }

    function testRepayBorrow() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));

        deal(WETH, address(wallet), 10 ether);

        vm.startPrank(address(wallet));
        IERC20(WETH).approve(comet, 10 ether);
        IComet(comet).supply(WETH, 10 ether);
        IComet(comet).withdraw(USDC, 1000e6);
        vm.stopPrank();

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            terminalScript,
            abi.encodeWithSelector(CometSupplyActions.supply.selector, comet, USDC, 1000e6),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        assertEq(IComet(comet).borrowBalanceOf(address(wallet)), 1000e6);
        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 10 ether);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertEq(IComet(comet).borrowBalanceOf(address(wallet)), 0e6);
        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 10 ether);
    }

    function testSupplyMultipleCollateral() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));

        deal(WETH, address(wallet), 10 ether);
        deal(LINK, address(wallet), 10e18);
        deal(USDC, address(wallet), 1000e6);

        address[] memory assets = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        assets[0] = WETH;
        assets[1] = LINK;
        assets[2] = USDC;
        amounts[0] = 10 ether;
        amounts[1] = 10e18;
        amounts[2] = 1000e6;

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            terminalScript,
            abi.encodeWithSelector(CometSupplyActions.supplyMultipleAssets.selector, comet, assets, amounts),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 10 ether);
        assertEq(IERC20(LINK).balanceOf(address(wallet)), 10e18);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 10 ether);
        assertEq(IComet(comet).collateralBalanceOf(address(wallet), LINK), 10e18);
        assertApproxEqAbs(IComet(comet).balanceOf(address(wallet)), 1000e6, 1);
    }
}
