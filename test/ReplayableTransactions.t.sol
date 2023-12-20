// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";
import {QuarkWallet, QuarkWalletStandalone} from "quark-core/src/QuarkWallet.sol";

import {RecurringPurchase} from "test/lib/RecurringPurchase.sol";

import {YulHelper} from "test/lib/YulHelper.sol";
import {SignatureHelper} from "test/lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "test/lib/QuarkOperationHelper.sol";

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

// TODO: Limit orders
// TODO: Liquidation protection
contract ReplayableTransactionsTest is Test {
    event Ping(uint256);
    event ClearNonce(address indexed wallet, uint96 nonce);

    CodeJar public codeJar;
    QuarkStateManager public stateManager;

    uint256 alicePrivateKey = 0x8675309;
    address aliceAccount = vm.addr(alicePrivateKey);
    QuarkWallet aliceWallet; // see constructor()

    bytes recurringPurchase = new YulHelper().getDeployed("RecurringPurchase.sol/RecurringPurchase.json");

    // Contracts address on mainnet
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    // Uniswap router info on mainnet
    address constant uniswapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    constructor() {
        // Fork setup
        vm.createSelectFork(
            string.concat(
                "https://node-provider.compound.finance/ethereum-mainnet/", vm.envString("NODE_PROVIDER_BYPASS_KEY")
            ),
            18429607 // 2023-10-25 13:24:00 PST
        );

        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        stateManager = new QuarkStateManager();
        console.log("QuarkStateManager deployed to: %s", address(stateManager));

        aliceWallet = new QuarkWalletStandalone(aliceAccount, address(0), codeJar, stateManager);
        console.log("Alice signer: %s", aliceAccount);
        console.log("Alice wallet at: %s", address(aliceWallet));
    }

    /* ===== recurring purchase tests ===== */

    function createPurchaseConfig(uint40 purchaseInterval, uint256 timesToPurchase, uint216 totalAmountToPurchase)
        internal
        view
        returns (RecurringPurchase.PurchaseConfig memory)
    {
        uint256 deadline = block.timestamp + purchaseInterval * (timesToPurchase - 1) + 1;
        RecurringPurchase.SwapParamsExactOut memory swapParams = RecurringPurchase.SwapParamsExactOut({
            uniswapRouter: uniswapRouter,
            recipient: address(aliceWallet),
            tokenFrom: USDC,
            amount: uint256(totalAmountToPurchase) / timesToPurchase,
            amountInMaximum: 30_000e6,
            deadline: deadline,
            path: abi.encodePacked(WETH, uint24(500), USDC) // Path: WETH - 0.05% -> USDC
        });
        RecurringPurchase.PurchaseConfig memory purchaseConfig = RecurringPurchase.PurchaseConfig({
            interval: purchaseInterval,
            totalAmountToPurchase: totalAmountToPurchase,
            swapParams: swapParams
        });
        return purchaseConfig;
    }

    // Executes the script once for gas measurement purchases
    function testRecurringPurchaseHappyPath() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        deal(USDC, address(aliceWallet), 100_000e6);
        uint40 purchaseInterval = 86_400; // 1 day interval
        uint256 timesToPurchase = 1;
        uint216 totalAmountToPurchase = 10 ether;
        RecurringPurchase.PurchaseConfig memory purchaseConfig =
            createPurchaseConfig(purchaseInterval, timesToPurchase, totalAmountToPurchase);
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringPurchase,
            abi.encodeWithSelector(RecurringPurchase.purchase.selector, purchaseConfig),
            ScriptType.ScriptAddress
        );
        op.expiry = purchaseConfig.swapParams.deadline;
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 0 ether);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op, v1, r1, s1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), totalAmountToPurchase);
    }

    function testRecurringPurchaseMultiplePurchases() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        deal(USDC, address(aliceWallet), 100_000e6);
        uint40 purchaseInterval = 86_400; // 1 day interval
        uint256 timesToPurchase = 2;
        uint216 totalAmountToPurchase = 20 ether;
        RecurringPurchase.PurchaseConfig memory purchaseConfig =
            createPurchaseConfig(purchaseInterval, timesToPurchase, totalAmountToPurchase);
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringPurchase,
            abi.encodeWithSelector(RecurringPurchase.purchase.selector, purchaseConfig),
            ScriptType.ScriptAddress
        );
        op.expiry = purchaseConfig.swapParams.deadline;
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 0 ether);

        // gas: meter execute
        vm.resumeGasMetering();
        // 1. Execute recurring purchase for the first time
        aliceWallet.executeQuarkOperation(op, v1, r1, s1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 10 ether);

        // 2a. Cannot buy again unless time interval has passed
        vm.expectRevert(RecurringPurchase.PurchaseConditionNotMet.selector);
        aliceWallet.executeQuarkOperation(op, v1, r1, s1);

        // 2b. Execute recurring purchase a second time after warping 1 day
        vm.warp(block.timestamp + purchaseInterval);
        aliceWallet.executeQuarkOperation(op, v1, r1, s1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 20 ether);
    }

    function testCancelRecurringPurchase() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        deal(USDC, address(aliceWallet), 100_000e6);
        uint40 purchaseInterval = 86_400; // 1 day interval
        uint256 timesToPurchase = 2;
        uint216 totalAmountToPurchase = 20 ether;
        RecurringPurchase.PurchaseConfig memory purchaseConfig =
            createPurchaseConfig(purchaseInterval, timesToPurchase, totalAmountToPurchase);
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringPurchase,
            abi.encodeWithSelector(RecurringPurchase.purchase.selector, purchaseConfig),
            ScriptType.ScriptAddress
        );
        op.expiry = purchaseConfig.swapParams.deadline;
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        QuarkWallet.QuarkOperation memory cancelOp = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringPurchase,
            abi.encodeWithSelector(RecurringPurchase.cancel.selector),
            ScriptType.ScriptAddress
        );
        (uint8 v2, bytes32 r2, bytes32 s2) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, cancelOp);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 0 ether);

        // gas: meter execute
        vm.resumeGasMetering();
        // 1. Execute recurring purchase for the first time
        aliceWallet.executeQuarkOperation(op, v1, r1, s1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 10 ether);

        // 2. Cancel replayable transaction
        aliceWallet.executeQuarkOperation(cancelOp, v2, r2, s2);

        // 3. Replayable transaction can no longer be executed
        vm.warp(block.timestamp + purchaseInterval);
        vm.expectRevert(QuarkStateManager.NonceAlreadySet.selector);
        aliceWallet.executeQuarkOperation(op, v1, r1, s1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 10 ether);
    }

    function testRecurringPurchaseWithDifferentCalldata() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        deal(USDC, address(aliceWallet), 100_000e6);
        uint40 purchaseInterval = 86_400; // 1 day interval
        QuarkWallet.QuarkOperation memory op1;
        QuarkWallet.QuarkOperation memory op2;
        QuarkWallet.QuarkOperation memory cancelOp;
        // Local scope to avoid stack too deep
        {
            uint256 timesToPurchase = 3;
            uint216 totalAmountToPurchase1 = 30 ether; // 10 ETH / day
            uint216 totalAmountToPurchase2 = 15 ether; // 5 ETH / day
            // Two purchase configs using the same nonce: one to purchase 10 ETH and the other to purchase 5 ETH
            RecurringPurchase.PurchaseConfig memory purchaseConfig1 =
                createPurchaseConfig(purchaseInterval, timesToPurchase, totalAmountToPurchase1);
            op1 = new QuarkOperationHelper().newBasicOpWithCalldata(
                aliceWallet,
                recurringPurchase,
                abi.encodeWithSelector(RecurringPurchase.purchase.selector, purchaseConfig1),
                ScriptType.ScriptAddress
            );
            op1.expiry = purchaseConfig1.swapParams.deadline;
            RecurringPurchase.PurchaseConfig memory purchaseConfig2 =
                createPurchaseConfig(purchaseInterval, timesToPurchase, totalAmountToPurchase2);
            op2 = new QuarkOperationHelper().newBasicOpWithCalldata(
                aliceWallet,
                recurringPurchase,
                abi.encodeWithSelector(RecurringPurchase.purchase.selector, purchaseConfig2),
                ScriptType.ScriptAddress
            );
            op2.expiry = purchaseConfig2.swapParams.deadline;
            cancelOp = new QuarkOperationHelper().newBasicOpWithCalldata(
                aliceWallet,
                recurringPurchase,
                abi.encodeWithSelector(RecurringPurchase.cancel.selector),
                ScriptType.ScriptAddress
            );
            cancelOp.expiry = op2.expiry;
        }
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op1);
        (uint8 v2, bytes32 r2, bytes32 s2) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op2);
        (uint8 v3, bytes32 r3, bytes32 s3) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, cancelOp);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 0 ether);

        // gas: meter execute
        vm.resumeGasMetering();
        // 1a. Execute recurring purchase order #1
        aliceWallet.executeQuarkOperation(op1, v1, r1, s1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 10 ether);

        // 1b. Execute recurring purchase order #2
        aliceWallet.executeQuarkOperation(op2, v2, r2, s2);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 15 ether);

        // 2. Warp until next purchase period
        vm.warp(block.timestamp + purchaseInterval);

        // 3a. Execute recurring purchase order #1
        aliceWallet.executeQuarkOperation(op1, v1, r1, s1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 25 ether);

        // 3b. Execute recurring purchase order #2
        aliceWallet.executeQuarkOperation(op2, v2, r2, s2);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 30 ether);

        // 4. Cancel replayable transaction
        aliceWallet.executeQuarkOperation(cancelOp, v3, r3, s3);

        // 5. Warp until next purchase period
        vm.warp(block.timestamp + purchaseInterval);

        // 6. Both recurring purchase orders can no longer be executed
        vm.expectRevert(QuarkStateManager.NonceAlreadySet.selector);
        aliceWallet.executeQuarkOperation(op1, v1, r1, s1);
        vm.expectRevert(QuarkStateManager.NonceAlreadySet.selector);
        aliceWallet.executeQuarkOperation(op2, v2, r2, s2);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 30 ether);
    }

    function testRevertsForPurchaseBeforeNextPurchasePeriod() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        deal(USDC, address(aliceWallet), 100_000e6);
        uint40 purchaseInterval = 86_400; // 1 day interval
        uint256 timesToPurchase = 2;
        uint216 totalAmountToPurchase = 20 ether;
        RecurringPurchase.PurchaseConfig memory purchaseConfig =
            createPurchaseConfig(purchaseInterval, timesToPurchase, totalAmountToPurchase);
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringPurchase,
            abi.encodeWithSelector(RecurringPurchase.purchase.selector, purchaseConfig),
            ScriptType.ScriptAddress
        );
        op.expiry = purchaseConfig.swapParams.deadline;
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 0 ether);

        // gas: meter execute
        vm.resumeGasMetering();
        // 1. Execute recurring purchase for the first time
        aliceWallet.executeQuarkOperation(op, v1, r1, s1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 10 ether);

        // 2. Cannot buy again unless time interval has passed
        vm.expectRevert(RecurringPurchase.PurchaseConditionNotMet.selector);
        aliceWallet.executeQuarkOperation(op, v1, r1, s1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 10 ether);
    }

    function testRevertsForExpiredQuarkOperation() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        deal(USDC, address(aliceWallet), 100_000e6);
        uint40 purchaseInterval = 86_400; // 1 day interval
        uint256 timesToPurchase = 1;
        uint216 totalAmountToPurchase = 10 ether;
        RecurringPurchase.PurchaseConfig memory purchaseConfig =
            createPurchaseConfig(purchaseInterval, timesToPurchase, totalAmountToPurchase);
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringPurchase,
            abi.encodeWithSelector(RecurringPurchase.purchase.selector, purchaseConfig),
            ScriptType.ScriptAddress
        );
        op.expiry = block.timestamp - 1; // Set Quark operation expiry to always expire
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert(QuarkWallet.SignatureExpired.selector);
        aliceWallet.executeQuarkOperation(op, v1, r1, s1);
    }

    function testRevertsForExpiredUniswapParams() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        deal(USDC, address(aliceWallet), 100_000e6);
        uint40 purchaseInterval = 86_400; // 1 day interval
        uint256 timesToPurchase = 1;
        uint216 totalAmountToPurchase = 10 ether;
        RecurringPurchase.PurchaseConfig memory purchaseConfig =
            createPurchaseConfig(purchaseInterval, timesToPurchase, totalAmountToPurchase);
        purchaseConfig.swapParams.deadline = block.timestamp - 1; // Set Uniswap deadline to always expire
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringPurchase,
            abi.encodeWithSelector(RecurringPurchase.purchase.selector, purchaseConfig),
            ScriptType.ScriptAddress
        );
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert(bytes("Transaction too old"));
        aliceWallet.executeQuarkOperation(op, v1, r1, s1);
    }

    function testRevertsForPurchasingOverTheLimit() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();

        deal(USDC, address(aliceWallet), 100_000e6);
        uint40 purchaseInterval = 86_400; // 1 day interval
        uint256 timesToPurchase = 2;
        uint216 totalAmountToPurchase = 20 ether; // 10 ETH / day
        RecurringPurchase.PurchaseConfig memory purchaseConfig =
            createPurchaseConfig(purchaseInterval, timesToPurchase, totalAmountToPurchase);
        purchaseConfig.totalAmountToPurchase = 10 ether; // Will only be able to purchase once
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            recurringPurchase,
            abi.encodeWithSelector(RecurringPurchase.purchase.selector, purchaseConfig),
            ScriptType.ScriptAddress
        );
        op.expiry = purchaseConfig.swapParams.deadline;
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 0 ether);

        // gas: meter execute
        vm.resumeGasMetering();
        // 1. Execute recurring purchase
        aliceWallet.executeQuarkOperation(op, v1, r1, s1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 10 ether);

        // 2. Warp until next purchase period
        vm.warp(block.timestamp + purchaseInterval);

        // 3. Purchasing again will go over the `totalAmountToPurchase` cap
        vm.expectRevert(RecurringPurchase.PurchaseConditionNotMet.selector);
        aliceWallet.executeQuarkOperation(op, v1, r1, s1);

        assertEq(IERC20(WETH).balanceOf(address(aliceWallet)), 10 ether);
    }
}
