// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";

import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkNonceManager} from "quark-core/src/QuarkNonceManager.sol";

import {QuarkWalletProxyFactory} from "quark-proxy/src/QuarkWalletProxyFactory.sol";

import {Ethcall} from "quark-core-scripts/src/Ethcall.sol";
import {ConditionalMulticall, ConditionalChecker} from "quark-core-scripts/src/ConditionalMulticall.sol";

import {Counter} from "test/lib/Counter.sol";

import {YulHelper} from "test/lib/YulHelper.sol";
import {SignatureHelper} from "test/lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "test/lib/QuarkOperationHelper.sol";

import {IComet} from "test/quark-core-scripts/interfaces/IComet.sol";

contract ConditionalMulticallTest is Test {
    QuarkWalletProxyFactory public factory;
    Counter public counter;
    uint256 alicePrivateKey = 0xa11ce;
    address alice = vm.addr(alicePrivateKey);

    // Comet address in mainnet
    address constant comet = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    // Uniswap router info on mainnet
    address constant uniswapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    bytes ethcall = new YulHelper().getCode("Ethcall.sol/Ethcall.json");
    bytes conditionalMulticall = new YulHelper().getCode("ConditionalMulticall.sol/ConditionalMulticall.json");
    address ethcallAddress;

    function setUp() public {
        vm.createSelectFork(
            string.concat(
                "https://node-provider.compound.finance/ethereum-mainnet/", vm.envString("NODE_PROVIDER_BYPASS_KEY")
            ),
            18429607 // 2023-10-25 13:24:00 PST
        );
        factory = new QuarkWalletProxyFactory(address(new QuarkWallet(new CodeJar(), new QuarkNonceManager())));
        counter = new Counter();
        counter.setNumber(0);
        ethcallAddress = QuarkWallet(payable(factory.walletImplementation())).codeJar().saveCode(ethcall);
        QuarkWallet(payable(factory.walletImplementation())).codeJar().saveCode(conditionalMulticall);
    }

    function testConditionalRunPassed() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        // Set up some funds for test
        deal(WETH, address(wallet), 100 ether);
        // Compose array of parameters
        address[] memory callContracts = new address[](5);
        bytes[] memory callDatas = new bytes[](5);
        ConditionalChecker.Condition[] memory conditions = new ConditionalChecker.Condition[](5);
        bytes[] memory checkValues = new bytes[](5);

        // Approve Comet to spend WETH
        callContracts[0] = ethcallAddress;
        callDatas[0] =
            abi.encodeWithSelector(Ethcall.run.selector, WETH, abi.encodeCall(IERC20.approve, (comet, 100 ether)), 0);
        conditions[0] = ConditionalChecker.Condition({
            checkType: ConditionalChecker.CheckType.Bool,
            operator: ConditionalChecker.Operator.Equal
        });
        checkValues[0] = abi.encode(true);

        // Supply WETH to Comet
        callContracts[1] = ethcallAddress;
        callDatas[1] =
            abi.encodeWithSelector(Ethcall.run.selector, comet, abi.encodeCall(IComet.supply, (WETH, 100 ether)), 0);
        conditions[1] = ConditionalChecker.Condition({
            checkType: ConditionalChecker.CheckType.None,
            operator: ConditionalChecker.Operator.None
        });
        checkValues[1] = hex"";

        // Withdraw USDC from Comet
        callContracts[2] = ethcallAddress;
        callDatas[2] = abi.encodeWithSelector(
            Ethcall.run.selector, comet, abi.encodeCall(IComet.withdraw, (USDC, 1_000_000_000)), 0
        );
        conditions[2] = ConditionalChecker.Condition({
            checkType: ConditionalChecker.CheckType.None,
            operator: ConditionalChecker.Operator.None
        });
        checkValues[2] = hex"";

        // Condition checks, account is not liquidatable
        callContracts[3] = ethcallAddress;
        callDatas[3] = abi.encodeWithSelector(
            Ethcall.run.selector, comet, abi.encodeCall(IComet.isLiquidatable, (address(wallet))), 0
        );
        conditions[3] = ConditionalChecker.Condition({
            checkType: ConditionalChecker.CheckType.Bool,
            operator: ConditionalChecker.Operator.Equal
        });
        checkValues[3] = abi.encode(false);

        // Condition checks that account borrow balance is 1000
        callContracts[4] = ethcallAddress;
        callDatas[4] = abi.encodeWithSelector(
            Ethcall.run.selector, comet, abi.encodeCall(IComet.borrowBalanceOf, (address(wallet))), 0
        );
        conditions[4] = ConditionalChecker.Condition({
            checkType: ConditionalChecker.CheckType.Uint,
            operator: ConditionalChecker.Operator.Equal
        });
        checkValues[4] = abi.encode(uint256(1000e6));

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            conditionalMulticall,
            abi.encodeWithSelector(ConditionalMulticall.run.selector, callContracts, callDatas, conditions, checkValues),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);

        // When reaches here, meaning all checks are passed
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 1_000_000_000);
    }

    function testConditionalRunUnmet() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        // Set up some funds for test
        deal(WETH, address(wallet), 100 ether);
        // Compose array of parameters
        address[] memory callContracts = new address[](2);
        bytes[] memory callDatas = new bytes[](2);
        ConditionalChecker.Condition[] memory conditions = new ConditionalChecker.Condition[](2);
        bytes[] memory checkValues = new bytes[](2);

        // Approve Comet to spend WETH
        callContracts[0] = ethcallAddress;
        callDatas[0] =
            abi.encodeWithSelector(Ethcall.run.selector, WETH, abi.encodeCall(IERC20.approve, (comet, 100 ether)), 0);
        conditions[0] = ConditionalChecker.Condition({
            checkType: ConditionalChecker.CheckType.Bool,
            operator: ConditionalChecker.Operator.Equal
        });
        checkValues[0] = abi.encode(false);

        // Supply WETH to Comet
        callContracts[1] = ethcallAddress;
        callDatas[1] =
            abi.encodeWithSelector(Ethcall.run.selector, comet, abi.encodeCall(IComet.supply, (WETH, 100 ether)), 0);
        conditions[1] = ConditionalChecker.Condition({
            checkType: ConditionalChecker.CheckType.None,
            operator: ConditionalChecker.Operator.None
        });
        checkValues[1] = hex"";

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            conditionalMulticall,
            abi.encodeWithSelector(ConditionalMulticall.run.selector, callContracts, callDatas, conditions, checkValues),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        vm.expectRevert(
            abi.encodeWithSelector(
                ConditionalChecker.CheckFailed.selector,
                abi.encode(true),
                abi.encode(false),
                ConditionalChecker.CheckType.Bool,
                ConditionalChecker.Operator.Equal
            )
        );
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
    }

    function testConditionalRunInvalidInput() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        // Compose array of parameters
        address[] memory callContracts = new address[](2);
        bytes[] memory callDatas = new bytes[](1);
        ConditionalChecker.Condition[] memory conditions = new ConditionalChecker.Condition[](0);
        bytes[] memory checkValues = new bytes[](0);

        callContracts[0] = ethcallAddress;
        callDatas[0] = abi.encodeWithSelector(
            Ethcall.run.selector, address(counter), abi.encodeWithSignature("increment(uint256)", (20))
        );
        callContracts[1] = ethcallAddress;

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            conditionalMulticall,
            abi.encodeWithSelector(ConditionalMulticall.run.selector, callContracts, callDatas, conditions, checkValues),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        vm.expectRevert(abi.encodeWithSelector(ConditionalMulticall.InvalidInput.selector));
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
    }

    function testConditionalRunMulticallError() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        // Set up some funds for test
        deal(WETH, address(wallet), 100 ether);

        // Compose array of parameters
        address[] memory callContracts = new address[](4);
        bytes[] memory callDatas = new bytes[](4);
        ConditionalChecker.Condition[] memory conditions = new ConditionalChecker.Condition[](4);
        bytes[] memory checkValues = new bytes[](4);

        // Approve Comet to spend WETH
        callContracts[0] = ethcallAddress;
        callDatas[0] =
            abi.encodeWithSelector(Ethcall.run.selector, WETH, abi.encodeCall(IERC20.approve, (comet, 100 ether)), 0);
        conditions[0] = ConditionalChecker.Condition({
            checkType: ConditionalChecker.CheckType.Bool,
            operator: ConditionalChecker.Operator.Equal
        });
        checkValues[0] = abi.encode(true);

        // Supply WETH to Comet
        callContracts[1] = ethcallAddress;
        callDatas[1] =
            abi.encodeWithSelector(Ethcall.run.selector, comet, abi.encodeCall(IComet.supply, (WETH, 100 ether)), 0);
        conditions[1] = ConditionalChecker.Condition({
            checkType: ConditionalChecker.CheckType.None,
            operator: ConditionalChecker.Operator.None
        });
        checkValues[1] = hex"";

        // Withdraw USDC from Comet
        callContracts[2] = ethcallAddress;
        callDatas[2] =
            abi.encodeWithSelector(Ethcall.run.selector, comet, abi.encodeCall(IComet.withdraw, (USDC, 1000e6)), 0);
        conditions[2] = ConditionalChecker.Condition({
            checkType: ConditionalChecker.CheckType.None,
            operator: ConditionalChecker.Operator.None
        });
        checkValues[2] = hex"";

        // Send USDC to Stranger; will fail (insufficient balance)
        callContracts[3] = ethcallAddress;
        callDatas[3] = abi.encodeWithSelector(
            Ethcall.run.selector, USDC, abi.encodeCall(IERC20.transfer, (address(123), 10_000e6)), 0
        );
        conditions[3] = ConditionalChecker.Condition({
            checkType: ConditionalChecker.CheckType.None,
            operator: ConditionalChecker.Operator.None
        });
        checkValues[3] = hex"";

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            conditionalMulticall,
            abi.encodeWithSelector(ConditionalMulticall.run.selector, callContracts, callDatas, conditions, checkValues),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        vm.expectRevert(
            abi.encodeWithSelector(
                ConditionalMulticall.MulticallError.selector,
                3,
                callContracts[3],
                abi.encodeWithSignature("Error(string)", "ERC20: transfer amount exceeds balance")
            )
        );
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
    }

    function testConditionalRunEmptyInputIsValid() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        // Compose array of parameters
        address[] memory callContracts = new address[](0);
        bytes[] memory callDatas = new bytes[](0);
        ConditionalChecker.Condition[] memory conditions = new ConditionalChecker.Condition[](0);
        bytes[] memory checkValues = new bytes[](0);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            conditionalMulticall,
            abi.encodeWithSelector(ConditionalMulticall.run.selector, callContracts, callDatas, conditions, checkValues),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // Empty array is a valid input representing a no-op, and it should not revert
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
    }

    function testConditionalRunOnPeriodicRepay() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        // Set up some funds for test
        deal(WETH, address(wallet), 100 ether);
        vm.startPrank(address(wallet));
        IERC20(WETH).approve(comet, 100 ether);
        IERC20(USDC).approve(comet, type(uint256).max);
        IComet(comet).supply(WETH, 100 ether);
        IComet(comet).withdraw(USDC, 1000e6);
        IERC20(USDC).transfer(address(1), 1000e6); // Spent somewhere else
        vm.stopPrank();

        // Compose array of parameters
        address[] memory callContracts = new address[](3);
        bytes[] memory callDatas = new bytes[](3);
        ConditionalChecker.Condition[] memory conditions = new ConditionalChecker.Condition[](3);
        bytes[] memory checkValues = new bytes[](3);

        // Monitor wallet balance, if it ever goes over 400 USDC, it will start repaying Comet if borrowBalance is still > 0
        // Check wallet balance of USDC
        callContracts[0] = ethcallAddress;
        callDatas[0] =
            abi.encodeWithSelector(Ethcall.run.selector, USDC, abi.encodeCall(IERC20.balanceOf, (address(wallet))), 0);
        conditions[0] = ConditionalChecker.Condition({
            checkType: ConditionalChecker.CheckType.Uint,
            operator: ConditionalChecker.Operator.GreaterThanOrEqual
        });
        checkValues[0] = abi.encode(uint256(400e6));

        // Check that wallet still has USDC borrow in Comet
        callContracts[1] = ethcallAddress;
        callDatas[1] = abi.encodeWithSelector(
            Ethcall.run.selector, comet, abi.encodeCall(IComet.borrowBalanceOf, (address(wallet))), 0
        );
        conditions[1] = ConditionalChecker.Condition({
            checkType: ConditionalChecker.CheckType.Uint,
            operator: ConditionalChecker.Operator.GreaterThan
        });
        checkValues[1] = abi.encode(uint256(0));

        // Supply USDC to Comet to repay
        callContracts[2] = ethcallAddress;
        callDatas[2] =
            abi.encodeWithSelector(Ethcall.run.selector, comet, abi.encodeCall(IComet.supply, (USDC, 400e6)), 0);
        conditions[2] = ConditionalChecker.Condition({
            checkType: ConditionalChecker.CheckType.None,
            operator: ConditionalChecker.Operator.None
        });
        checkValues[2] = hex"";

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            conditionalMulticall,
            abi.encodeWithSelector(ConditionalMulticall.run.selector, callContracts, callDatas, conditions, checkValues),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        // Wallet doesn't have USDC, condition will fail
        vm.expectRevert(
            abi.encodeWithSelector(
                ConditionalChecker.CheckFailed.selector,
                abi.encode(uint256(0)),
                abi.encode(uint256(400e6)),
                ConditionalChecker.CheckType.Uint,
                ConditionalChecker.Operator.GreaterThanOrEqual
            )
        );
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);

        vm.pauseGasMetering();
        // Wallet has accrue 400 USDC
        deal(USDC, address(wallet), 400e6);

        // Condition met should repay Comet
        op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            conditionalMulticall,
            abi.encodeWithSelector(ConditionalMulticall.run.selector, callContracts, callDatas, conditions, checkValues),
            ScriptType.ScriptAddress
        );
        (v, r, s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);

        vm.pauseGasMetering();
        // Wallet has accrued another 400 USDC
        deal(USDC, address(wallet), 400e6);
        op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            conditionalMulticall,
            abi.encodeWithSelector(ConditionalMulticall.run.selector, callContracts, callDatas, conditions, checkValues),
            ScriptType.ScriptAddress
        );
        (v, r, s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);

        vm.pauseGasMetering();
        // Wallet has accrued another 400 USDC
        deal(USDC, address(wallet), 400e6);
        op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            conditionalMulticall,
            abi.encodeWithSelector(ConditionalMulticall.run.selector, callContracts, callDatas, conditions, checkValues),
            ScriptType.ScriptAddress
        );
        (v, r, s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);

        vm.pauseGasMetering();
        // Wallet no longer borrows from Comet, condition 2 will fail
        deal(USDC, address(wallet), 400e6);

        op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            conditionalMulticall,
            abi.encodeWithSelector(ConditionalMulticall.run.selector, callContracts, callDatas, conditions, checkValues),
            ScriptType.ScriptAddress
        );
        (v, r, s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        vm.expectRevert(
            abi.encodeWithSelector(
                ConditionalChecker.CheckFailed.selector,
                abi.encode(uint256(0)),
                abi.encode(uint256(0)),
                ConditionalChecker.CheckType.Uint,
                ConditionalChecker.Operator.GreaterThan
            )
        );
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);

        // Wallet fully pays off debt
        assertEq(IComet(comet).borrowBalanceOf(address(wallet)), 0);
    }
}
