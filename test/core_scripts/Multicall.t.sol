// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";
import "forge-std/interfaces/IERC20.sol";

import "./../../src/QuarkWallet.sol";
import "./../../src/QuarkWalletFactory.sol";
import "./../../src/core_scripts/MultiCall.sol";
import "./../../src/core_scripts/lib/ConditionalChecker.sol";
import "./../lib/YulHelper.sol";
import "./../lib/SignatureHelper.sol";
import "./../lib/Counter.sol";
import "./interfaces/IComet.sol";

contract MultiCallTest is Test {
    QuarkWalletFactory public factory;
    Counter public counter;
    // For signature to QuarkWallet
    uint256 alicePK = 0xa11ce;
    address alice = vm.addr(alicePK);
    SignatureHelper public signatureHelper;

    // Comet address in mainnet
    address constant comet = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    // Uniswap router info on mainnet
    address constant uniswapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    function setUp() public {
        factory = new QuarkWalletFactory();
        signatureHelper = new SignatureHelper();
        counter = new Counter();
        counter.setNumber(0);
    }

    // Tests for run
    function testInvokeCounterTwice() public {
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        bytes memory multiCall = new YulHelper().getDeployed(
            "MultiCall.sol/MultiCall.json"
        );

        // Compose array of parameters
        address[] memory callContracts = new address[](2);
        bytes[] memory callDatas = new bytes[](2);
        uint256[] memory callValues = new uint256[](2);
        callContracts[0] = address(counter);
        callDatas[0] = abi.encodeWithSignature("increment(uint256)", (20));
        callValues[0] = 0 wei;
        callContracts[1] = address(counter);
        callDatas[1] = abi.encodeWithSignature("decrement(uint256)", (5));
        callValues[1] = 0 wei;

        assertEq(counter.number(), 0);

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(MultiCall.run.selector, callContracts, callDatas, callValues),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (uint8 v, bytes32 r, bytes32 s) = signatureHelper.signOp(alicePK, wallet, op);
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(counter.number(), 15);
    }

    function testSupplyWETHWithdrawUSDCOnComet() public {
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        bytes memory multiCall = new YulHelper().getDeployed(
            "MultiCall.sol/MultiCall.json"
        );

        // Set up some funds for test
        deal(WETH, address(wallet), 100 ether);

        // Compose array of parameters
        address[] memory callContracts = new address[](3);
        bytes[] memory callDatas = new bytes[](3);
        uint256[] memory callValues = new uint256[](3);

        // Approve Comet to spend USDC
        callContracts[0] = address(WETH);
        callDatas[0] = abi.encodeCall(IERC20.approve, (comet, 100 ether));
        callValues[0] = 0 wei;

        // Supply WETH to Comet
        callContracts[1] = comet;
        callDatas[1] = abi.encodeCall(IComet.supply, (WETH, 100 ether));
        callValues[1] = 0 wei;

        // Withdraw USDC from Comet
        callContracts[2] = comet;
        callDatas[2] = abi.encodeCall(IComet.withdraw, (USDC, 1000e6));
        callValues[2] = 0 wei;

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(MultiCall.run.selector, callContracts, callDatas, callValues),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (uint8 v, bytes32 r, bytes32 s) = signatureHelper.signOp(alicePK, wallet, op);
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(IERC20(USDC).balanceOf(address(wallet)), 1000e6);
    }

    // Tests for runWithConditionalCheck
    function testConditionalCheckSimplePassed() public {
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        bytes memory multiCall = new YulHelper().getDeployed(
            "MultiCall.sol/MultiCall.json"
        );

        // Set up some funds for test
        deal(WETH, address(wallet), 100 ether);
        // Compose array of parameters
        address[] memory callContracts = new address[](5);
        bytes[] memory callDatas = new bytes[](5);
        uint256[] memory callValues = new uint256[](5);
        ConditionalChecker.CheckType[] memory checkTypes = new ConditionalChecker.CheckType[](5);
        ConditionalChecker.Operator[] memory operators = new ConditionalChecker.Operator[](5);
        bytes[] memory checkValues = new bytes[](5);

        // Approve Comet to spend WETH
        callContracts[0] = WETH;
        callDatas[0] = abi.encodeCall(IERC20.approve, (comet, 100 ether));
        callValues[0] = 0 wei;
        checkTypes[0] = ConditionalChecker.CheckType.Bool;
        operators[0] = ConditionalChecker.Operator.Equal;
        checkValues[0] = abi.encode(true);

        // Supply WETH to Comet
        callContracts[1] = comet;
        callDatas[1] = abi.encodeCall(IComet.supply, (WETH, 100 ether));
        callValues[1] = 0 wei;
        checkTypes[1] = ConditionalChecker.CheckType.None;
        operators[1] = ConditionalChecker.Operator.None;
        checkValues[1] = hex"";

        // Withdraw USDC from Comet
        callContracts[2] = comet;
        callDatas[2] = abi.encodeCall(IComet.withdraw, (USDC, 1_000_000_000));
        callValues[2] = 0 wei;
        checkTypes[2] = ConditionalChecker.CheckType.None;
        operators[2] = ConditionalChecker.Operator.None;
        checkValues[2] = hex"";

        // Condition checks, account is not liquidatable
        callContracts[3] = comet;
        callDatas[3] = abi.encodeCall(IComet.isLiquidatable, (address(wallet)));
        callValues[3] = 0 wei;
        checkTypes[3] = ConditionalChecker.CheckType.Bool;
        operators[3] = ConditionalChecker.Operator.Equal;
        checkValues[3] = abi.encode(false);

        // Condition checks that account borrow balance is 1000
        callContracts[4] = comet;
        callDatas[4] = abi.encodeCall(IComet.borrowBalanceOf, (address(wallet)));
        callValues[4] = 0 wei;
        checkTypes[4] = ConditionalChecker.CheckType.Uint;
        operators[4] = ConditionalChecker.Operator.Equal;
        checkValues[4] = abi.encode(uint256(1000e6));

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(
                MultiCall.runWithConditionalCheck.selector,
                callContracts,
                callDatas,
                callValues,
                checkTypes,
                operators,
                checkValues
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (uint8 v, bytes32 r, bytes32 s) = signatureHelper.signOp(alicePK, wallet, op);
        wallet.executeQuarkOperation(op, v, r, s);

        // When reaches here, meaning all checks are passed
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 1_000_000_000);
    }

    function testConditionalCheckSimpleUnmet() public {
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        bytes memory multiCall = new YulHelper().getDeployed(
            "MultiCall.sol/MultiCall.json"
        );

        // Set up some funds for test
        deal(WETH, address(wallet), 100 ether);
        // Compose array of parameters
        address[] memory callContracts = new address[](2);
        bytes[] memory callDatas = new bytes[](2);
        uint256[] memory callValues = new uint256[](2);
        ConditionalChecker.CheckType[] memory checkTypes = new ConditionalChecker.CheckType[](2);
        ConditionalChecker.Operator[] memory operators = new ConditionalChecker.Operator[](2);
        bytes[] memory checkValues = new bytes[](2);

        // Approve Comet to spend WETH
        callContracts[0] = WETH;
        callDatas[0] = abi.encodeCall(IERC20.approve, (comet, 100 ether));
        callValues[0] = 0 wei;
        checkTypes[0] = ConditionalChecker.CheckType.Bool;
        operators[0] = ConditionalChecker.Operator.Equal;
        checkValues[0] = abi.encode(false);

        // Supply WETH to Comet
        callContracts[1] = comet;
        callDatas[1] = abi.encodeCall(IComet.supply, (WETH, 100 ether));
        callValues[1] = 0 wei;
        checkTypes[1] = ConditionalChecker.CheckType.None;
        operators[1] = ConditionalChecker.Operator.None;
        checkValues[1] = hex"";

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(
                MultiCall.runWithConditionalCheck.selector,
                callContracts,
                callDatas,
                callValues,
                checkTypes,
                operators,
                checkValues
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (uint8 v, bytes32 r, bytes32 s) = signatureHelper.signOp(alicePK, wallet, op);

        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector,
                abi.encodeWithSelector(
                    ConditionalChecker.CheckFailed.selector,
                    abi.encode(true),
                    abi.encode(false),
                    ConditionalChecker.CheckType.Bool,
                    ConditionalChecker.Operator.Equal
                )
            )
        );
        wallet.executeQuarkOperation(op, v, r, s);
    }

    function testConditionalChecksOnPeriodicRepay() public {
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        bytes memory multiCall = new YulHelper().getDeployed(
            "MultiCall.sol/MultiCall.json"
        );

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
        uint256[] memory callValues = new uint256[](3);
        ConditionalChecker.CheckType[] memory checkTypes = new ConditionalChecker.CheckType[](3);
        ConditionalChecker.Operator[] memory operators = new ConditionalChecker.Operator[](3);
        bytes[] memory checkValues = new bytes[](3);

        // Monitor wallet balance, if it ever goes over 400 USDC, it will start repaying Comet if borrowBalance is still > 0
        // Check wallet balance of USDC
        callContracts[0] = USDC;
        callDatas[0] = abi.encodeCall(IERC20.balanceOf, (address(wallet)));
        callValues[0] = 0 wei;
        checkTypes[0] = ConditionalChecker.CheckType.Uint;
        operators[0] = ConditionalChecker.Operator.GreaterThanOrEqual;
        checkValues[0] = abi.encode(uint256(400e6));

        // Check that wallet still has USDC borrow in Comet
        callContracts[1] = comet;
        callDatas[1] = abi.encodeCall(IComet.borrowBalanceOf, (address(wallet)));
        callValues[1] = 0 wei;
        checkTypes[1] = ConditionalChecker.CheckType.Uint;
        operators[1] = ConditionalChecker.Operator.GreaterThan;
        checkValues[1] = abi.encode(uint256(0));

        // Supply USDC to Comet to repay
        callContracts[2] = comet;
        callDatas[2] = abi.encodeCall(IComet.supply, (USDC, 400e6));
        callValues[2] = 0 wei;
        checkTypes[2] = ConditionalChecker.CheckType.None;
        operators[2] = ConditionalChecker.Operator.None;
        checkValues[2] = hex"";

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(
                MultiCall.runWithConditionalCheck.selector,
                callContracts,
                callDatas,
                callValues,
                checkTypes,
                operators,
                checkValues
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (uint8 v, bytes32 r, bytes32 s) = signatureHelper.signOp(alicePK, wallet, op);
        // Wallet doesn't have USDC, condition will fail
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector,
                abi.encodeWithSelector(
                    ConditionalChecker.CheckFailed.selector,
                    abi.encode(uint256(0)),
                    abi.encode(uint256(400e6)),
                    ConditionalChecker.CheckType.Uint,
                    ConditionalChecker.Operator.GreaterThanOrEqual
                )
            )
        );
        wallet.executeQuarkOperation(op, v, r, s);

        // Wallet has accrue 400 USDC
        deal(USDC, address(wallet), 400e6);

        // Condition met should repay Comet
        op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(
                MultiCall.runWithConditionalCheck.selector,
                callContracts,
                callDatas,
                callValues,
                checkTypes,
                operators,
                checkValues
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (v, r, s) = signatureHelper.signOp(alicePK, wallet, op);
        wallet.executeQuarkOperation(op, v, r, s);

        // Wallet has accrued another 400 USDC
        deal(USDC, address(wallet), 400e6);
        op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(
                MultiCall.runWithConditionalCheck.selector,
                callContracts,
                callDatas,
                callValues,
                checkTypes,
                operators,
                checkValues
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (v, r, s) = signatureHelper.signOp(alicePK, wallet, op);
        wallet.executeQuarkOperation(op, v, r, s);

        // Wallet has accrued another 400 USDC
        deal(USDC, address(wallet), 400e6);
        op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(
                MultiCall.runWithConditionalCheck.selector,
                callContracts,
                callDatas,
                callValues,
                checkTypes,
                operators,
                checkValues
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (v, r, s) = signatureHelper.signOp(alicePK, wallet, op);
        wallet.executeQuarkOperation(op, v, r, s);

        // Wallet no longer borrows from Comet, condition 2 will fail
        deal(USDC, address(wallet), 400e6);

        op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(
                MultiCall.runWithConditionalCheck.selector,
                callContracts,
                callDatas,
                callValues,
                checkTypes,
                operators,
                checkValues
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (v, r, s) = signatureHelper.signOp(alicePK, wallet, op);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector,
                abi.encodeWithSelector(
                    ConditionalChecker.CheckFailed.selector,
                    abi.encode(uint256(0)),
                    abi.encode(uint256(0)),
                    ConditionalChecker.CheckType.Uint,
                    ConditionalChecker.Operator.GreaterThan
                )
            )
        );
        wallet.executeQuarkOperation(op, v, r, s);

        // Wallet fully pays off debt
        assertEq(IComet(comet).borrowBalanceOf(address(wallet)), 0);
    }
}
