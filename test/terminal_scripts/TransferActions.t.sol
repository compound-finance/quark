// SPDX-License-Identifier: UNLICENSED
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
import "./../lib/EvilReceiver.sol";

/**
 * Scenario test for uesr borrow base asset from Comet v3 market
 */

contract TransferActionsTest is Test {
    QuarkWalletFactory public factory;
    Counter public counter;
    uint256 alicePrivateKey = 0xa11ce;
    address alice = vm.addr(alicePrivateKey);
    uint256 bobPrivateKey = 0xb0b;
    address bob = vm.addr(bobPrivateKey);
    bytes terminalScript = new YulHelper().getDeployed(
            "TerminalScript.sol/TransferActions.json"
        );

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
        wallet.executeQuarkOperation(op, v, r, s);
        // assert on native ETH balance
        assertEq(address(wallet).balance, 0 ether);
        assertEq(address(walletBob).balance, 10 ether);
    }

    function testTranferReentrancyAttack() public {
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
        vm.expectRevert();
        wallet.executeQuarkOperation(op, v, r, s);
        assertEq(address(wallet).balance, 10 ether);
        assertEq(address(evilReceiver).balance, 0 ether);
    }

    function testTransferReentranctAttackWithStolenSignature() public {
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
        // Not replayable signature will blocked by QuarkWallet during executeQuarkOperation
        vm.expectRevert();
        wallet.executeQuarkOperation(op, v, r, s);
        // assert on native ETH balance
        assertEq(address(wallet).balance, 10 ether);
        assertEq(address(evilReceiver).balance, 0 ether);
    }
}
