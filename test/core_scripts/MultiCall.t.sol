// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";
import "forge-std/interfaces/IERC20.sol";

import "./../../src/CodeJar.sol";
import "./../../src/QuarkWallet.sol";
import "./../../src/core_scripts/CoreScript.sol";
import "./../../src/core_scripts/MultiCall.sol";
import "./../../src/core_scripts/lib/ConditionChecks.sol";
import "./../lib/YulHelper.sol";
import "./../lib/SignatureHelper.sol";
import "./../lib/Counter.sol";
import "./scripts/SupplyComet.sol";
import "./scripts/EveryMondayTriggerCondition.sol";
import "./scripts/IsMonday.sol";
import "./scripts/WeeklyTriggerCondition.sol";
import "./interfaces/IComet.sol";
import "./interfaces/ISwapRouter.sol";

contract MultiCallTest is Test {
    CodeJar public codeJar;
    Counter public counter;
    // For signature to QuarkWallet
    address constant alice = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint256 constant alicePK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    SignatureHelper public signatureHelper;

    // Comet address in mainnet
    address constant comet = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    // Router info on mainnet
    address constant router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    address conditionChecks;

    function setUp() public {
        signatureHelper = new SignatureHelper();
        codeJar = new CodeJar();
        codeJar.saveCode(
            new YulHelper().getDeployed(
                "MultiCall.sol/MultiCall.json"
            )
        );

        counter = new Counter();
        counter.setNumber(0);

        // Load condition checks
        // Load addresses via code jar for the check contract
        conditionChecks = codeJar.saveCode(
            new YulHelper().getDeployed(
                "ConditionChecks.sol/ConditionChecks.json"
            )
        );
    }

    // Test #1: Invoke Counter twice via signature
    function testMultiCallCounter() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(alice, codeJar);
        bytes memory multiCall = new YulHelper().getDeployed(
            "MultiCall.sol/MultiCall.json"
        );

        // Compose array of parameters
        address[] memory callContracts = new address[](2);
        bytes[] memory callDatas = new bytes[](2);
        uint256[] memory callValues = new uint256[](2);
        callContracts[0] = address(counter);
        callDatas[0] = abi.encodeCall(Counter.incrementBy, (20));
        callValues[0] = 0 wei;
        callContracts[1] = address(counter);
        callDatas[1] = abi.encodeCall(Counter.decrementBy, (5));
        callValues[1] = 0 wei;

        assertEq(counter.number(), 0);

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(MultiCall.run.selector, callContracts, callDatas, callValues),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (uint8 v, bytes32 r, bytes32 s) = signatureHelper.signOp(wallet, op, alicePK);
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(counter.number(), 15);
    }

    // Test #2: Supply ETH and withdraw USDC on Comet
    function testMultiCallSupplyEthAndWithdrawUSDC() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(alice, codeJar);
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

        // Supply ETH to Comet
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
        (uint8 v, bytes32 r, bytes32 s) = signatureHelper.signOp(wallet, op, alicePK);
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(IERC20(USDC).balanceOf(address(wallet)), 1000e6);
    }

    // Test #3: MultiCall with array returns
    function testMultiCallWithArrayOfReturns() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(alice, codeJar);
        bytes memory multiCall = new YulHelper().getDeployed(
            "MultiCall.sol/MultiCall.json"
        );

        // Set up some funds for test
        deal(WETH, address(wallet), 100 ether);

        // Compose array of parameters
        address[] memory callContracts = new address[](6);
        bytes[] memory callDatas = new bytes[](6);
        uint256[] memory callValues = new uint256[](6);

        // Approve Comet to spend USDC
        callContracts[0] = WETH;
        callDatas[0] = abi.encodeCall(IERC20.approve, (comet, 100 ether));
        callValues[0] = 0 wei;

        // Supply ETH to Comet
        callContracts[1] = comet;
        callDatas[1] = abi.encodeCall(IComet.supply, (WETH, 100 ether));
        callValues[1] = 0 wei;

        // Withdraw USDC from Comet
        callContracts[2] = comet;
        callDatas[2] = abi.encodeCall(IComet.withdraw, (USDC, 1000e6));
        callValues[2] = 0 wei;

        // Get balance of USDC of the wallet
        callContracts[3] = USDC;
        callDatas[3] = abi.encodeCall(IERC20.balanceOf, (address(wallet)));
        callValues[3] = 0 wei;

        // Get balance of WETH of the wallet
        callContracts[4] = WETH;
        callDatas[4] = abi.encodeCall(IERC20.balanceOf, (address(wallet)));
        callValues[4] = 0 wei;

        // Get borrow balance of USDC of the wallet
        callContracts[5] = comet;
        callDatas[5] = abi.encodeCall(IComet.borrowBalanceOf, (address(wallet)));
        callValues[5] = 0 wei;

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(MultiCall.runWithReturns.selector, callContracts, callDatas, callValues),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (uint8 v, bytes32 r, bytes32 s) = signatureHelper.signOp(wallet, op, alicePK);
        bytes memory returnData = wallet.executeQuarkOperation(op, v, r, s);

        bytes[] memory data = abi.decode(returnData, (bytes[]));
        // Check on the last three return values
        // Assert balance of USDC is 1000
        assertEq(abi.decode(data[3], (uint256)), 1000e6);
        // Assert WETH balance is 0
        assertEq(abi.decode(data[4], (uint256)), 0);
        // Assert borrow balance is 1000
        assertEq(abi.decode(data[5], (uint256)), 1000e6);
    }

    // Test #4: MultiCall with checks simple passed
    function testMultiCallWithChecksSimplePassed() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(alice, codeJar);
        bytes memory multiCall = new YulHelper().getDeployed(
            "MultiCall.sol/MultiCall.json"
        );

        // Set up some funds for test
        deal(WETH, address(wallet), 100 ether);
        // Compose array of parameters
        address[] memory callContracts = new address[](5);
        bytes[] memory callDatas = new bytes[](5);
        uint256[] memory callValues = new uint256[](5);
        address[] memory checkContracts = new address[](5);
        bytes4[] memory checkSelectors = new bytes4[](5);
        bytes[] memory checkValues = new bytes[](5);

        // Approve Comet to spend USDC
        callContracts[0] = WETH;
        callDatas[0] = abi.encodeCall(IERC20.approve, (comet, 100 ether));
        callValues[0] = 0 wei;
        checkContracts[0] = conditionChecks;
        checkSelectors[0] = ConditionChecks.isTrue.selector;
        checkValues[0] = hex"";

        // Supply ETH to Comet
        callContracts[1] = comet;
        callDatas[1] = abi.encodeCall(IComet.supply, (WETH, 100 ether));
        callValues[1] = 0 wei;
        checkContracts[1] = address(0);
        checkSelectors[1] = hex"";
        checkValues[1] = hex"";

        // Withdraw USDC from Comet
        callContracts[2] = comet;
        callDatas[2] = abi.encodeCall(IComet.withdraw, (USDC, 1000_000_000));
        callValues[2] = 0 wei;
        checkContracts[2] = address(0);
        checkSelectors[2] = hex"";
        checkValues[2] = hex"";

        // Condition checks, account is not liquidatable
        callContracts[3] = comet;
        callDatas[3] = abi.encodeCall(IComet.isLiquidatable, (address(wallet)));
        callValues[3] = 0 wei;
        checkContracts[3] = conditionChecks;
        checkSelectors[3] = ConditionChecks.isFalse.selector;
        checkValues[3] = hex"";

        // Condition checks, account borrow balance is 1000
        callContracts[4] = comet;
        callDatas[4] = abi.encodeCall(IComet.borrowBalanceOf, (address(wallet)));
        callValues[4] = 0 wei;
        checkContracts[4] = conditionChecks;
        checkSelectors[4] = ConditionChecks.uint256Eq.selector;
        checkValues[4] = abi.encode(uint256(1000e6));

        // Condition checks, account balance of ETH is 0
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(
                MultiCall.runWithChecks.selector,
                callContracts,
                callDatas,
                callValues,
                checkContracts,
                checkSelectors,
                checkValues
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (uint8 v, bytes32 r, bytes32 s) = signatureHelper.signOp(wallet, op, alicePK);
        wallet.executeQuarkOperation(op, v, r, s);

        // When reaches here, meaning all checks are passed
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 1000_000_000);
    }

    // Test #5: MultiCall with checks simple failed
    function testMultiCallWithChecksSimpleUnmetCondition() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(alice, codeJar);
        bytes memory multiCall = new YulHelper().getDeployed(
            "MultiCall.sol/MultiCall.json"
        );

        // Set up some funds for test
        deal(WETH, address(wallet), 100 ether);
        // Compose array of parameters
        address[] memory callContracts = new address[](2);
        bytes[] memory callDatas = new bytes[](2);
        uint256[] memory callValues = new uint256[](2);
        address[] memory checkContracts = new address[](2);
        bytes4[] memory checkSelectors = new bytes4[](2);
        bytes[] memory checkValues = new bytes[](2);

        // Approve Comet to spend USDC
        callContracts[0] = WETH;
        callDatas[0] = abi.encodeCall(IERC20.approve, (comet, 100 ether));
        callValues[0] = 0 wei;
        checkContracts[0] = conditionChecks;
        checkSelectors[0] = ConditionChecks.isFalse.selector;
        checkValues[0] = hex"";

        // Supply ETH to Comet
        callContracts[1] = comet;
        callDatas[1] = abi.encodeCall(IComet.supply, (WETH, 100 ether));
        callValues[1] = 0 wei;
        checkContracts[1] = address(0);
        checkSelectors[1] = hex"";
        checkValues[1] = hex"";

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(
                MultiCall.runWithChecks.selector,
                callContracts,
                callDatas,
                callValues,
                checkContracts,
                checkSelectors,
                checkValues
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (uint8 v, bytes32 r, bytes32 s) = signatureHelper.signOp(wallet, op, alicePK);

        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector,
                abi.encodeWithSelector(
                    CoreScript.MultiCallCheckError.selector,
                    0,
                    callContracts[0],
                    callDatas[0],
                    callValues[0],
                    abi.encode(true),
                    checkContracts[0],
                    checkSelectors[0],
                    hex"",
                    abi.encodeWithSelector(ConditionChecks.CheckFailed.selector)
                )
            )
        );
        wallet.executeQuarkOperation(op, v, r, s);
    }

    // Test #6: MultiCall with condition that wallet only repay when wallet accrue some USDC/ETH and owe to Comet at the same time
    function testMultiCallWithChecksOnConditionalRepay() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(alice, codeJar);
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
        address[] memory callContracts = new address[](4);
        bytes[] memory callDatas = new bytes[](4);
        uint256[] memory callValues = new uint256[](4);
        address[] memory checkContracts = new address[](4);
        bytes4[] memory checkSelectors = new bytes4[](4);
        bytes[] memory checkValues = new bytes[](4);

        // Monitor wallet balance, if it ever goes over 400 USDC, it will start repaying Comet if borrowBalance is still > 0
        // Check wallet balance of USDC
        callContracts[0] = USDC;
        callDatas[0] = abi.encodeCall(IERC20.balanceOf, (address(wallet)));
        callValues[0] = 0 wei;
        checkContracts[0] = conditionChecks;
        checkSelectors[0] = ConditionChecks.uint256Gte.selector;
        checkValues[0] = abi.encode(uint256(400e6));

        // Check still owe Comet USDC
        callContracts[1] = comet;
        callDatas[1] = abi.encodeCall(IComet.borrowBalanceOf, (address(wallet)));
        callValues[1] = 0 wei;
        checkContracts[1] = conditionChecks;
        checkSelectors[1] = ConditionChecks.uint256Gt.selector;
        checkValues[1] = abi.encode(uint256(0));

        // Supply USDC to Comet to repay
        callContracts[2] = comet;
        callDatas[2] = abi.encodeCall(IComet.supply, (USDC, 400e6));
        callValues[2] = 0 wei;
        checkContracts[2] = address(0);
        checkSelectors[2] = hex"";
        checkValues[2] = hex"";

        // Condition checks, account has less than threshold
        callContracts[3] = USDC;
        callDatas[3] = abi.encodeCall(IERC20.balanceOf, (address(wallet)));
        callValues[3] = 0 wei;
        checkContracts[3] = conditionChecks;
        checkSelectors[3] = ConditionChecks.uint256Lt.selector;
        checkValues[3] = abi.encode(uint256(400e6));

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(
                MultiCall.runWithChecks.selector,
                callContracts,
                callDatas,
                callValues,
                checkContracts,
                checkSelectors,
                checkValues
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (uint8 v, bytes32 r, bytes32 s) = signatureHelper.signOp(wallet, op, alicePK);
        // Wallet doen't have USDC, condition will fail
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector,
                abi.encodeWithSelector(
                    CoreScript.MultiCallCheckError.selector,
                    0,
                    callContracts[0],
                    callDatas[0],
                    callValues[0],
                    abi.encode(uint256(0)),
                    checkContracts[0],
                    checkSelectors[0],
                    checkValues[0],
                    abi.encodeWithSelector(ConditionChecks.CheckFailed.selector)
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
                MultiCall.runWithChecks.selector,
                callContracts,
                callDatas,
                callValues,
                checkContracts,
                checkSelectors,
                checkValues
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (v, r, s) = signatureHelper.signOp(wallet, op, alicePK);
        wallet.executeQuarkOperation(op, v, r, s);

        // Wallet has accrue another 400 USDC
        deal(USDC, address(wallet), 400e6);
        op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(
                MultiCall.runWithChecks.selector,
                callContracts,
                callDatas,
                callValues,
                checkContracts,
                checkSelectors,
                checkValues
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (v, r, s) = signatureHelper.signOp(wallet, op, alicePK);
        wallet.executeQuarkOperation(op, v, r, s);

        // Wallet has accrue another 400 USDC
        deal(USDC, address(wallet), 400e6);
        op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(
                MultiCall.runWithChecks.selector,
                callContracts,
                callDatas,
                callValues,
                checkContracts,
                checkSelectors,
                checkValues
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (v, r, s) = signatureHelper.signOp(wallet, op, alicePK);
        wallet.executeQuarkOperation(op, v, r, s);

        // Wallet no longer owe Comet, condition#2 will fail
        deal(USDC, address(wallet), 400e6);

        op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(
                MultiCall.runWithChecks.selector,
                callContracts,
                callDatas,
                callValues,
                checkContracts,
                checkSelectors,
                checkValues
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (v, r, s) = signatureHelper.signOp(wallet, op, alicePK);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector,
                abi.encodeWithSelector(
                    CoreScript.MultiCallCheckError.selector,
                    1,
                    callContracts[1],
                    callDatas[1],
                    callValues[1],
                    abi.encode(uint256(0)),
                    checkContracts[1],
                    checkSelectors[1],
                    checkValues[1],
                    abi.encodeWithSelector(ConditionChecks.CheckFailed.selector)
                )
            )
        );
        wallet.executeQuarkOperation(op, v, r, s);

        // Wallet fully pays off debt
        assertEq(IComet(comet).borrowBalanceOf(address(wallet)), 0);
    }

    // Test #7: MultiCall test to use SupplyComet scripts to supply and borrow in one transaction
    function testApproveSupplyCometInCustomScript() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(alice, codeJar);
        bytes memory multiCall = new YulHelper().getDeployed(
            "MultiCall.sol/MultiCall.json"
        );
        address cometSupply = codeJar.saveCode(
            new YulHelper().getDeployed(
                "SupplyComet.sol/SupplyComet.json"
            )
        );

        // Set up some funds for test
        deal(WETH, address(wallet), 100 ether);
        // Compose array of parameters
        address[] memory callContracts = new address[](4);
        bytes[] memory callDatas = new bytes[](4);
        uint256[] memory callValues = new uint256[](4);

        // Approve Comet to spend USDC
        callContracts[0] = WETH;
        callDatas[0] = abi.encodeCall(IERC20.approve, (comet, 100 ether));
        callValues[0] = 0 wei;

        // Allow supplyComet script
        callContracts[1] = comet;
        callDatas[1] = abi.encodeCall(IComet.allow, (cometSupply, true));
        callValues[1] = 0 wei;

        // Execute script
        callContracts[2] = cometSupply;
        callDatas[2] = abi.encodeCall(SupplyComet.supplyAndBorrow, (comet, WETH, 100 ether, USDC, 1000e6));
        callValues[2] = 0 wei;

        // Revoke allow
        callContracts[3] = comet;
        callDatas[3] = abi.encodeCall(IComet.allow, (cometSupply, false));
        callValues[3] = 0 wei;

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(MultiCall.run.selector, callContracts, callDatas, callValues),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (uint8 v, bytes32 r, bytes32 s) = signatureHelper.signOp(wallet, op, alicePK);
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(IERC20(USDC).balanceOf(address(wallet)), 1000_000_000);
    }

    // Test #8: MultiCall to execute buy every Monday with custom scripts
    function testBuyEthEveryMonday() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(alice, codeJar);
        bytes memory multiCall = new YulHelper().getDeployed(
            "MultiCall.sol/MultiCall.json"
        );
        address everyMondayTriggerCondition = codeJar.saveCode(
            new YulHelper().getDeployed(
                "EveryMondayTriggerCondition.sol/EveryMondayTriggerCondition.json"
            )
        );

        // Set up some funds (10k USDC) for test
        deal(USDC, address(wallet), 10000e6);
        // Warp to Thursday
        vm.warp(block.timestamp / 1 weeks * 1 weeks);

        // Compose array of parameters
        address[] memory callContracts = new address[](3);
        bytes[] memory callDatas = new bytes[](3);
        uint256[] memory callValues = new uint256[](3);

        // Execute everyMondayTriggerCondition script
        callContracts[0] = everyMondayTriggerCondition;
        callDatas[0] = abi.encodeCall(EveryMondayTriggerCondition.timeToWeeklyRun, ());
        callValues[0] = 0 wei;

        // Approve router to spend USDC
        callContracts[1] = USDC;
        callDatas[1] = abi.encodeCall(IERC20.approve, (router, 1000e6));
        callValues[1] = 0 wei;

        // Swap 1000USDC for WETH via router
        callContracts[2] = address(router);
        callDatas[2] = abi.encodeCall(
            ISwapRouter.exactInputSingle,
            (
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: USDC,
                    tokenOut: WETH,
                    fee: 500, // 0.05%
                    recipient: address(wallet),
                    deadline: type(uint256).max, // Set to max for easier re-run in the test
                    amountIn: 1000e6,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            )
        );
        callValues[2] = 0 wei;

        // It's not Monday yet, so will revert
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(MultiCall.run.selector, callContracts, callDatas, callValues),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (uint8 v, bytes32 r, bytes32 s) = signatureHelper.signOp(wallet, op, alicePK);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector,
                abi.encodeWithSelector(
                    CoreScript.MultiCallError.selector,
                    0,
                    callContracts[0],
                    callDatas[0],
                    callValues[0],
                    abi.encodeWithSelector(EveryMondayTriggerCondition.NotMonday.selector)
                )
            )
        );
        wallet.executeQuarkOperation(op, v, r, s);

        // Warp to Monday
        vm.warp(block.timestamp / 1 weeks * 1 weeks + 4 days);
        op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(MultiCall.run.selector, callContracts, callDatas, callValues),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (v, r, s) = signatureHelper.signOp(wallet, op, alicePK);
        wallet.executeQuarkOperation(op, v, r, s);

        // Last run just completed, need to wait 7 days to buy eth again
        op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(MultiCall.run.selector, callContracts, callDatas, callValues),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (v, r, s) = signatureHelper.signOp(wallet, op, alicePK);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector,
                abi.encodeWithSelector(
                    CoreScript.MultiCallError.selector,
                    0,
                    callContracts[0],
                    callDatas[0],
                    callValues[0],
                    abi.encodeWithSelector(WeeklyTriggerCondition.ConditionFailed.selector)
                )
            )
        );
        wallet.executeQuarkOperation(op, v, r, s);

        // Warp to next Monday
        vm.warp(block.timestamp / 1 weeks * 1 weeks + 11 days + 6 hours); // Add additional 6 hours, simulate couple hours in the middle of the day
        op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(MultiCall.run.selector, callContracts, callDatas, callValues),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (v, r, s) = signatureHelper.signOp(wallet, op, alicePK);
        wallet.executeQuarkOperation(op, v, r, s);

        // Successfully bought 2 times
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 8000e6);
    }

    // Test #9: MultiCall to execute buy every Monday with custom scripts and checks
    function testBuyEthEveryMondayWithChecks() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(alice, codeJar);
        bytes memory multiCall = new YulHelper().getDeployed(
            "MultiCall.sol/MultiCall.json"
        );
        // one time deploy EveryMondayTriggerCondition
        address isMonday = codeJar.saveCode(
            new YulHelper().getDeployed(
                "IsMonday.sol/IsMonday.json"
            )
        );

        // Set up some funds (10k USDC) for test
        deal(USDC, address(wallet), 10000e6);
        // Warp to Thursday
        vm.warp(block.timestamp / 1 weeks * 1 weeks);

        // Compose array of parameters
        address[] memory callContracts = new address[](3);
        bytes[] memory callDatas = new bytes[](3);
        uint256[] memory callValues = new uint256[](3);
        address[] memory checkContracts = new address[](3);
        bytes4[] memory checkSelectors = new bytes4[](3);
        bytes[] memory checkValues = new bytes[](3);

        // Execute everyMondayTriggerCondition script
        callContracts[0] = isMonday;
        callDatas[0] = abi.encodeCall(IsMonday.isMonday, ());
        callValues[0] = 0 wei;
        checkContracts[0] = conditionChecks;
        checkSelectors[0] = ConditionChecks.isTrue.selector;
        checkValues[0] = hex"";

        // Approve router to spend USDC
        callContracts[1] = USDC;
        callDatas[1] = abi.encodeCall(IERC20.approve, (router, 1000e6));
        callValues[1] = 0 wei;
        checkContracts[1] = conditionChecks;
        checkSelectors[1] = ConditionChecks.isTrue.selector;
        checkValues[1] = hex"";

        // Swap 1000USDC for WETH via router
        callContracts[2] = address(router);
        callDatas[2] = abi.encodeCall(
            ISwapRouter.exactInputSingle,
            (
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: USDC,
                    tokenOut: WETH,
                    fee: 500, // 0.05%
                    recipient: address(wallet),
                    deadline: type(uint256).max, // Set to max for easier re-run in the test
                    amountIn: 1000e6,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            )
        );
        callValues[2] = 0 wei;
        // Check minimum amount received is what we want along the way
        checkContracts[2] = conditionChecks;
        checkSelectors[2] = ConditionChecks.uint256Gte.selector;
        checkValues[2] = abi.encode(uint256(1e17)); // At least 0.1ETH

        // It's not Monday yet, so revert
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(
                MultiCall.runWithChecks.selector,
                callContracts,
                callDatas,
                callValues,
                checkContracts,
                checkSelectors,
                checkValues
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (uint8 v, bytes32 r, bytes32 s) = signatureHelper.signOp(wallet, op, alicePK);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector,
                abi.encodeWithSelector(
                    CoreScript.MultiCallCheckError.selector,
                    0,
                    callContracts[0],
                    callDatas[0],
                    callValues[0],
                    abi.encode(false),
                    checkContracts[0],
                    checkSelectors[0],
                    hex"",
                    abi.encodeWithSelector(ConditionChecks.CheckFailed.selector)
                )
            )
        );
        wallet.executeQuarkOperation(op, v, r, s);

        // Warp to Monday
        vm.warp(block.timestamp / 1 weeks * 1 weeks + 4 days);
        op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(
                MultiCall.runWithChecks.selector,
                callContracts,
                callDatas,
                callValues,
                checkContracts,
                checkSelectors,
                checkValues
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (v, r, s) = signatureHelper.signOp(wallet, op, alicePK);
        wallet.executeQuarkOperation(op, v, r, s);

        // Warp to Tuesday
        vm.warp(block.timestamp / 1 weeks * 1 weeks + 5 days);
        op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(
                MultiCall.runWithChecks.selector,
                callContracts,
                callDatas,
                callValues,
                checkContracts,
                checkSelectors,
                checkValues
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (v, r, s) = signatureHelper.signOp(wallet, op, alicePK);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector,
                abi.encodeWithSelector(
                    CoreScript.MultiCallCheckError.selector,
                    0,
                    callContracts[0],
                    callDatas[0],
                    callValues[0],
                    abi.encode(false),
                    checkContracts[0],
                    checkSelectors[0],
                    hex"",
                    abi.encodeWithSelector(ConditionChecks.CheckFailed.selector)
                )
            )
        );
        wallet.executeQuarkOperation(op, v, r, s);

        // Warp to next Monday
        vm.warp(block.timestamp / 1 weeks * 1 weeks + 11 days + 6 hours); // Add additional 6 hours, simulate couple hours in the middle of the day
        op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(
                MultiCall.runWithChecks.selector,
                callContracts,
                callDatas,
                callValues,
                checkContracts,
                checkSelectors,
                checkValues
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (v, r, s) = signatureHelper.signOp(wallet, op, alicePK);
        wallet.executeQuarkOperation(op, v, r, s);

        // Successfully bought 2 times
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 8000e6);
    }
}
