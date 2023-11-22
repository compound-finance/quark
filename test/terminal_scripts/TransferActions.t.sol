// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdMath.sol";

import "./../../src/CodeJar.sol";
import "./../../src/QuarkScript.sol";
import "./../../src/QuarkWallet.sol";
import "./../../src/QuarkWalletFactory.sol";
import "./../../src/terminal_scripts/TerminalScript.sol";
import "./../../src/core_scripts/Multicall.sol";
import "./../lib/AllowCallbacks.sol";
import "./../lib/YulHelper.sol";
import "./../lib/SignatureHelper.sol";
import "./../lib/Counter.sol";
import "./../lib/ReentrantTransfer.sol";
import "./../lib/QuarkOperationHelper.sol";
import "./../lib/EvilReceiver.sol";

/**
 * Tests for transferring assets
 */
contract TransferActionsTest is Test {
    QuarkWalletFactory public factory;
    CodeJar public codeJar;
    Counter public counter;
    uint256 alicePrivateKey = 0xa11ce;
    address alice = vm.addr(alicePrivateKey);
    uint256 bobPrivateKey = 0xb0b;
    address bob = vm.addr(bobPrivateKey);
    bytes terminalScript = new YulHelper().getDeployed(
            "TerminalScript.sol/TransferActions.json"
        );
    bytes multicall = new YulHelper().getDeployed(
            "Multicall.sol/Multicall.json"
        );
    bytes allowCallbacks = new YulHelper().getDeployed("AllowCallbacks.sol/AllowCallbacks.json");

    // Contracts address on mainnet
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function setUp() public {
        // Fork setup
        vm.createSelectFork(
            string.concat(
                "https://node-provider.compound.finance/ethereum-mainnet/", vm.envString("NODE_PROVIDER_BYPASS_KEY")
            ),
            18429607 // 2023-10-25 13:24:00 PST
        );
        factory = new QuarkWalletFactory();
        codeJar = factory.codeJar();
    }

    function testTransferERC20TokenToEOA() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));

        deal(WETH, address(wallet), 10 ether);

        assertEq(IERC20(WETH).balanceOf(address(wallet)), 10 ether);
        assertEq(IERC20(WETH).balanceOf(bob), 0 ether);
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            terminalScript,
            abi.encodeWithSelector(TransferActions.transferERC20Token.selector, WETH, bob, 10 ether),
            ScriptType.ScriptSource
        );

        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 0 ether);
        assertEq(IERC20(WETH).balanceOf(bob), 10 ether);
    }

    function testTransferERC20TokenToQuarkWallet() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        QuarkWallet walletBob = QuarkWallet(factory.create(bob, 0));

        deal(WETH, address(wallet), 10 ether);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 10 ether);
        assertEq(IERC20(WETH).balanceOf(bob), 0 ether);
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            terminalScript,
            abi.encodeWithSelector(
                TransferActions.transferERC20Token.selector, WETH, address(walletBob), 10 ether
                ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 0 ether);
        assertEq(IERC20(WETH).balanceOf(address(walletBob)), 10 ether);
    }

    function testTransferNativeTokenToEOA() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));

        deal(address(wallet), 10 ether);

        assertEq(address(wallet).balance, 10 ether);
        assertEq(bob.balance, 0 ether);
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            terminalScript,
            abi.encodeWithSelector(TransferActions.transferNativeToken.selector, bob, 10 ether),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        // assert on native ETH balance
        assertEq(address(wallet).balance, 0 ether);
        assertEq(bob.balance, 10 ether);
    }

    function testTransferNativeTokenToQuarkWallet() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        QuarkWallet walletBob = QuarkWallet(factory.create(bob, 0));
        deal(address(wallet), 10 ether);
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            terminalScript,
            abi.encodeWithSelector(
                TransferActions.transferNativeToken.selector, address(walletBob), 10 ether
                ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        assertEq(address(wallet).balance, 10 ether);
        assertEq(address(walletBob).balance, 0 ether);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        // assert on native ETH balance
        assertEq(address(wallet).balance, 0 ether);
        assertEq(address(walletBob).balance, 10 ether);
    }

    function testTransferReentrancyAttackSuccessWithCallbackEnabled() public {
        vm.pauseGasMetering();
        bytes memory reentrantTransfer = new YulHelper().getDeployed(
            "ReentrantTransfer.sol/ReentrantTransfer.json"
        );
        address allowCallbacksAddress = codeJar.saveCode(allowCallbacks);
        address reentrantTransferAddress = codeJar.saveCode(reentrantTransfer);
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        EvilReceiver evilReceiver = new EvilReceiver();
        evilReceiver.setAttack(
            EvilReceiver.ReentryAttack(EvilReceiver.AttackType.REINVOKE_TRANSFER, address(evilReceiver), 1 ether, 2)
        );
        deal(address(wallet), 10 ether);
        // Compose array of parameters
        address[] memory callContracts = new address[](2);
        bytes[] memory callDatas = new bytes[](2);
        callContracts[0] = allowCallbacksAddress;
        callDatas[0] = abi.encodeWithSelector(AllowCallbacks.run.selector, address(reentrantTransferAddress));
        callContracts[1] = reentrantTransferAddress;
        callDatas[1] =
            abi.encodeWithSelector(ReentrantTransfer.transferNativeToken.selector, address(evilReceiver), 1 ether);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            multicall,
            abi.encodeWithSelector(Multicall.run.selector, callContracts, callDatas),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        assertEq(address(wallet).balance, 10 ether);
        assertEq(address(evilReceiver).balance, 0 ether);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertEq(address(wallet).balance, 7 ether);
        assertEq(address(evilReceiver).balance, 3 ether);
    }

    function testRevertsForTransferReentrancyAttackWithReentrancyGuard() public {
        vm.pauseGasMetering();
        address allowCallbacksAddress = codeJar.saveCode(allowCallbacks);
        address terminalScriptAddress = codeJar.saveCode(terminalScript);
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        EvilReceiver evilReceiver = new EvilReceiver();
        evilReceiver.setAttack(
            EvilReceiver.ReentryAttack(EvilReceiver.AttackType.REINVOKE_TRANSFER, address(evilReceiver), 1 ether, 2)
        );
        deal(address(wallet), 10 ether);
        // Compose array of parameters
        address[] memory callContracts = new address[](2);
        bytes[] memory callDatas = new bytes[](2);
        callContracts[0] = allowCallbacksAddress;
        callDatas[0] = abi.encodeWithSelector(AllowCallbacks.run.selector, address(terminalScriptAddress));
        callContracts[1] = terminalScriptAddress;
        callDatas[1] =
            abi.encodeWithSelector(TransferActions.transferNativeToken.selector, address(evilReceiver), 1 ether);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            multicall,
            abi.encodeWithSelector(Multicall.run.selector, callContracts, callDatas),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        assertEq(address(wallet).balance, 10 ether);
        assertEq(address(evilReceiver).balance, 0 ether);
        vm.resumeGasMetering();
        vm.expectRevert(
            abi.encodeWithSelector(
                Multicall.MulticallError.selector,
                1,
                callContracts[1],
                abi.encodeWithSelector(
                    TransferActions.TransferFailed.selector, abi.encodeWithSelector(QuarkScript.ReentrantCall.selector)
                )
            )
        );
        wallet.executeQuarkOperation(op, v, r, s);
        assertEq(address(wallet).balance, 10 ether);
        assertEq(address(evilReceiver).balance, 0 ether);
    }

    function testRevertsForTransferReentrancyAttackWithoutCallbackEnabled() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        EvilReceiver evilReceiver = new EvilReceiver();
        evilReceiver.setAttack(
            EvilReceiver.ReentryAttack(EvilReceiver.AttackType.REINVOKE_TRANSFER, address(evilReceiver), 1 ether, 2)
        );
        deal(address(wallet), 10 ether);
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            terminalScript,
            abi.encodeWithSelector(
                TransferActions.transferNativeToken.selector, address(evilReceiver), 1 ether
                ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        assertEq(address(wallet).balance, 10 ether);
        assertEq(address(evilReceiver).balance, 0 ether);
        // Reentering into the QuarkWallet fails due to there being no active callback
        vm.expectRevert(
            abi.encodeWithSelector(
                TransferActions.TransferFailed.selector, abi.encodeWithSelector(QuarkWallet.NoActiveCallback.selector)
            )
        );
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertEq(address(wallet).balance, 10 ether);
        assertEq(address(evilReceiver).balance, 0 ether);
    }

    function testRevertsForTransferReentrantAttackWithStolenSignature() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        EvilReceiver evilReceiver = new EvilReceiver();
        evilReceiver.setAttack(
            EvilReceiver.ReentryAttack(EvilReceiver.AttackType.STOLEN_SIGNATURE, address(evilReceiver), 1 ether, 2)
        );
        deal(address(wallet), 10 ether);
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            terminalScript,
            abi.encodeWithSelector(
                TransferActions.transferNativeToken.selector, address(evilReceiver), 1 ether
                ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        evilReceiver.stealSignature(EvilReceiver.StolenSignature(op, v, r, s));

        assertEq(address(wallet).balance, 10 ether);
        assertEq(address(evilReceiver).balance, 0 ether);
        vm.resumeGasMetering();
        // Not replayable signature will blocked by QuarkWallet during executeQuarkOperation
        vm.expectRevert(
            abi.encodeWithSelector(
                TransferActions.TransferFailed.selector,
                abi.encodeWithSelector(QuarkStateManager.NonceAlreadySet.selector)
            )
        );
        wallet.executeQuarkOperation(op, v, r, s);
        // assert on native ETH balance
        assertEq(address(wallet).balance, 10 ether);
        assertEq(address(evilReceiver).balance, 0 ether);
    }
}
