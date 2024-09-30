// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdMath.sol";

import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkNonceManager} from "quark-core/src/QuarkNonceManager.sol";

import {QuarkWalletProxyFactory} from "quark-proxy/src/QuarkWalletProxyFactory.sol";

import {Ethcall} from "quark-core-scripts/src/Ethcall.sol";

import {YulHelper} from "test/lib/YulHelper.sol";
import {SignatureHelper} from "test/lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "test/lib/QuarkOperationHelper.sol";

import {Counter} from "test/lib/Counter.sol";

import {IComet} from "test/quark-core-scripts/interfaces/IComet.sol";

contract EthcallTest is Test {
    QuarkWalletProxyFactory public factory;
    Counter public counter;
    uint256 alicePrivateKey = 0xa11ce;
    address alice = vm.addr(alicePrivateKey);

    // Contracts address on mainnet
    address constant comet = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    bytes ethcall = new YulHelper().getCode("Ethcall.sol/Ethcall.json");

    function setUp() public {
        // Fork setup
        vm.createSelectFork(
            vm.envString("MAINNET_RPC_URL"),
            18429607 // 2023-10-25 13:24:00 PST
        );

        counter = new Counter();
        factory = new QuarkWalletProxyFactory(address(new QuarkWallet(new CodeJar(), new QuarkNonceManager())));
        counter.setNumber(0);
        QuarkWallet(payable(factory.walletImplementation())).codeJar().saveCode(ethcall);
    }

    function testEthcallCounter() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            ethcall,
            abi.encodeWithSelector(
                Ethcall.run.selector, address(counter), abi.encodeWithSignature("increment(uint256)", (1)), 0
            ),
            ScriptType.ScriptSource
        );

        assertEq(counter.number(), 0);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertEq(counter.number(), 1);
    }

    function testEthcallSupplyUSDCToComet() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        // Set up some funds for test
        deal(USDC, address(wallet), 1000e6);
        // Approve Comet to spend USDC
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            ethcall,
            abi.encodeWithSelector(
                Ethcall.run.selector, address(USDC), abi.encodeCall(IERC20.approve, (comet, 1000e6)), 0
            ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(IComet(comet).balanceOf(address(wallet)), 0);

        // gas: do not meter set-up
        vm.pauseGasMetering();
        // Supply Comet
        op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            ethcall,
            abi.encodeWithSelector(
                Ethcall.run.selector, address(comet), abi.encodeCall(IComet.supply, (USDC, 1000e6)), 0
            ),
            ScriptType.ScriptSource
        );
        (v, r, s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);

        // Since there is rouding diff, assert on diff is less than 10 wei
        assertApproxEqAbs(1000e6, IComet(comet).balanceOf(address(wallet)), 2);
    }

    function testEthcallWithdrawUSDCFromComet() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        // Set up some funds for test
        deal(WETH, address(wallet), 100 ether);

        // Approve Comet to spend WETH
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            ethcall,
            abi.encodeWithSelector(
                Ethcall.run.selector, address(WETH), abi.encodeCall(IERC20.approve, (comet, 100 ether)), 0
            ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);

        // gas: do not meter set-up
        vm.pauseGasMetering();
        // Supply WETH to Comet
        op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            ethcall,
            abi.encodeWithSelector(
                Ethcall.run.selector, address(comet), abi.encodeCall(IComet.supply, (WETH, 100 ether)), 0
            ),
            ScriptType.ScriptSource
        );
        (v, r, s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);

        // gas: do not meter set-up
        vm.pauseGasMetering();
        // Withdraw USDC from Comet
        op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            ethcall,
            abi.encodeWithSelector(
                Ethcall.run.selector, address(comet), abi.encodeCall(IComet.withdraw, (USDC, 1000e6)), 0
            ),
            ScriptType.ScriptSource
        );
        (v, r, s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(IERC20(USDC).balanceOf(address(wallet)), 1000e6);
    }

    function testEthcallCallReraiseError() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        // Set up some funds for test
        deal(USDC, address(wallet), 1000e6);

        // Send 2000 USDC to Comet
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            ethcall,
            abi.encodeWithSelector(
                Ethcall.run.selector, address(USDC), abi.encodeCall(IERC20.transfer, (comet, 2000e6)), 0
            ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        wallet.executeQuarkOperation(op, v, r, s);
    }

    function testEthcallShouldReturnCallResult() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        counter.setNumber(5);
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            ethcall,
            abi.encodeWithSelector(
                Ethcall.run.selector, address(counter), abi.encodeWithSignature("decrement(uint256)", (1)), 0
            ),
            ScriptType.ScriptSource
        );

        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory quarkReturn = wallet.executeQuarkOperation(op, v, r, s);
        bytes memory returnData = abi.decode(quarkReturn, (bytes));

        assertEq(counter.number(), 4);
        assertEq(abi.decode(returnData, (uint256)), 4);
    }
}
