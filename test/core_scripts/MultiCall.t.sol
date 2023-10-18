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
import "./../../src/core_scripts/lib/CheckIsTrue.sol";
import "./../../src/core_scripts/lib/CheckIsFalse.sol";
import "./../../src/core_scripts/lib/CheckUint256Gt.sol";
import "./../../src/core_scripts/lib/CheckUint256Gte.sol";
import "./../../src/core_scripts/lib/CheckUint256Lt.sol";
import "./../../src/core_scripts/lib/CheckUint256Eq.sol";
import "./../lib/YulHelper.sol";
import "./../lib/Counter.sol";
import "./scripts/SupplyComet.sol";
import "./scripts/EveryMondayTriggerCondition.sol";
import "./scripts/IsMonday.sol";
import "./scripts/WeeklyTriggerCondition.sol";
import "./interfaces/IComet.sol";
import "./interfaces/ISwapRouter.sol";

contract MultiCallTest is Test {
    CodeJar public codeJar;
    bytes32 internal constant QUARK_OPERATION_TYPEHASH =
        keccak256("QuarkOperation(bytes scriptSource,bytes scriptCalldata,uint256 nonce,uint256 expiry)");
    Counter public counter;
    // Comet address in mainnet
    address constant comet = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    // Router info on mainnet
    address constant router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    address checkIsTrue;
    address checkIsFalse;
    address checkUint256Gt;
    address checkUint256Lt;
    address checkUint256Eq;
    address checkUint256Gte;

    function setUp() public {
        codeJar = new CodeJar();
        codeJar.saveCode(
            new YulHelper().getDeployed(
                "MultiCall.sol/MultiCall.json"
            )
        );

        counter = new Counter();
        counter.setNumber(0);

        // Load condition checks
        // Load addresses via code jar for the check contracts
        checkIsTrue = codeJar.saveCode(
            new YulHelper().getDeployed(
                "CheckIsTrue.sol/CheckIsTrue.json"
            )
        );
        checkIsFalse = codeJar.saveCode(
            new YulHelper().getDeployed(
                "CheckIsFalse.sol/CheckIsFalse.json"
            )
        );
        checkUint256Gt = codeJar.saveCode(
            new YulHelper().getDeployed(
                "CheckUint256Gt.sol/CheckUint256Gt.json"
            )
        );
        checkUint256Lt = codeJar.saveCode(
            new YulHelper().getDeployed(
                "CheckUint256Lt.sol/CheckUint256Lt.json"
            )
        );
        checkUint256Eq = codeJar.saveCode(
            new YulHelper().getDeployed(
                "CheckUint256Eq.sol/CheckUint256Eq.json"
            )
        );
        checkUint256Gte = codeJar.saveCode(
            new YulHelper().getDeployed(
                "CheckUint256Gte.sol/CheckUint256Gte.json"
            )
        );
    }

    // Test #1: Invoke Counter twice via signature
    function testMultiCallCounter() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(address(this), codeJar);
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
        wallet.executeQuarkOperation(
            multiCall, abi.encodeWithSelector(MultiCall.run.selector, callContracts, callDatas, callValues), false
        );

        assertEq(counter.number(), 15);
    }

    // Test #2: Supply ETH and withdraw USDC on Comet
    function testMultiCallSupplyEthAndWithdrawUSDC() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(address(this), codeJar);
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
        callDatas[2] = abi.encodeCall(IComet.withdraw, (USDC, 1000_000_000));
        callValues[2] = 0 wei;

        wallet.executeQuarkOperation(
            multiCall, abi.encodeWithSelector(MultiCall.run.selector, callContracts, callDatas, callValues), false
        );

        assertEq(IERC20(USDC).balanceOf(address(wallet)), 1000_000_000);
    }

    // Test #3: MultiCall with array returns
    function testMultiCallWithArrayOfReturns() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(address(this), codeJar);
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

        bytes memory returnData = wallet.executeQuarkOperation(
            multiCall,
            abi.encodeWithSelector(MultiCall.runWithReturns.selector, callContracts, callDatas, callValues),
            false
        );

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
        QuarkWallet wallet = new QuarkWallet{salt: 0}(address(this), codeJar);
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
        bytes[] memory checkValues = new bytes[](5);

        // Approve Comet to spend USDC
        callContracts[0] = WETH;
        callDatas[0] = abi.encodeCall(IERC20.approve, (comet, 100 ether));
        callValues[0] = 0 wei;
        checkContracts[0] = checkIsTrue;
        checkValues[0] = hex"";

        // Supply ETH to Comet
        callContracts[1] = comet;
        callDatas[1] = abi.encodeCall(IComet.supply, (WETH, 100 ether));
        callValues[1] = 0 wei;
        checkContracts[1] = address(0);
        checkValues[1] = hex"";

        // Withdraw USDC from Comet
        callContracts[2] = comet;
        callDatas[2] = abi.encodeCall(IComet.withdraw, (USDC, 1000_000_000));
        callValues[2] = 0 wei;
        checkContracts[2] = address(0);
        checkValues[2] = hex"";

        // Condition checks, account is not liquidatable
        callContracts[3] = comet;
        callDatas[3] = abi.encodeCall(IComet.isLiquidatable, (address(wallet)));
        callValues[3] = 0 wei;
        checkContracts[3] = checkIsFalse;
        checkValues[3] = hex"";

        // Condition checks, account borrow balance is 1000
        callContracts[4] = comet;
        callDatas[4] = abi.encodeCall(IComet.borrowBalanceOf, (address(wallet)));
        callValues[4] = 0 wei;
        checkContracts[4] = checkUint256Eq;
        checkValues[4] = abi.encode(uint256(1000e6));

        // Condition checks, account balance of ETH is 0

        wallet.executeQuarkOperation(
            multiCall,
            abi.encodeWithSelector(
                MultiCall.runWithChecks.selector, callContracts, callDatas, callValues, checkContracts, checkValues
            ),
            false
        );

        // When reaches here, meaning all checks are passed
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 1000_000_000);
    }

    // Test #5: MultiCall with checks simple failed
    function testMultiCallWithChecksSimpleUnmetCondition() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(address(this), codeJar);
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
        bytes[] memory checkValues = new bytes[](2);

        // Approve Comet to spend USDC
        callContracts[0] = WETH;
        callDatas[0] = abi.encodeCall(IERC20.approve, (comet, 100 ether));
        callValues[0] = 0 wei;
        checkContracts[0] = checkIsFalse;
        checkValues[0] = hex"";

        // Supply ETH to Comet
        callContracts[1] = comet;
        callDatas[1] = abi.encodeCall(IComet.supply, (WETH, 100 ether));
        callValues[1] = 0 wei;
        checkContracts[1] = address(0);
        checkValues[1] = hex"";

        /// Expect CheckFailed() revert error from MultiCallCheckError from QuarkCallError
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
                    hex"",
                    abi.encodeWithSelector(CheckIsFalse.CheckFailed.selector)
                )
            )
        );
        wallet.executeQuarkOperation(
            multiCall,
            abi.encodeWithSelector(
                MultiCall.runWithChecks.selector, callContracts, callDatas, callValues, checkContracts, checkValues
            ),
            false
        );
    }

    // Test #6: MultiCall with condition that wallet only repay when wallet accrue some USDC/ETH and owe to Comet at the same time
    function testMultiCallWithChecksOnConditionalRepay() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(address(this), codeJar);
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
        bytes[] memory checkValues = new bytes[](4);

        // Monitor wallet balance, if it ever goes over 400 USDC, it will start repaying Comet if borrowBalance is still > 0
        // Check wallet balance of USDC
        callContracts[0] = USDC;
        callDatas[0] = abi.encodeCall(IERC20.balanceOf, (address(wallet)));
        callValues[0] = 0 wei;
        checkContracts[0] = checkUint256Gte;
        checkValues[0] = abi.encode(uint256(400e6));

        // Check still owe Comet USDC
        callContracts[1] = comet;
        callDatas[1] = abi.encodeCall(IComet.borrowBalanceOf, (address(wallet)));
        callValues[1] = 0 wei;
        checkContracts[1] = checkUint256Gt;
        checkValues[1] = abi.encode(uint256(0));

        // Supply USDC to Comet to repay
        callContracts[2] = comet;
        callDatas[2] = abi.encodeCall(IComet.supply, (USDC, 400e6));
        callValues[2] = 0 wei;
        checkContracts[2] = address(0);
        checkValues[2] = hex"";

        // Condition checks, account has less than threshold
        callContracts[3] = USDC;
        callDatas[3] = abi.encodeCall(IERC20.balanceOf, (address(wallet)));
        callValues[3] = 0 wei;
        checkContracts[3] = checkUint256Lt;
        checkValues[3] = abi.encode(uint256(400e6));

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
                    checkValues[0],
                    abi.encodeWithSelector(CheckUint256Gte.CheckFailed.selector)
                )
            )
        );
        wallet.executeQuarkOperation(
            multiCall,
            abi.encodeWithSelector(
                MultiCall.runWithChecks.selector, callContracts, callDatas, callValues, checkContracts, checkValues
            ),
            false
        );

        // Wallet has accue 400 USDC
        deal(USDC, address(wallet), 400e6);

        // Condition met should repay Comet
        wallet.executeQuarkOperation(
            multiCall,
            abi.encodeWithSelector(
                MultiCall.runWithChecks.selector, callContracts, callDatas, callValues, checkContracts, checkValues
            ),
            false
        );

        deal(USDC, address(wallet), 400e6);
        wallet.executeQuarkOperation(
            multiCall,
            abi.encodeWithSelector(
                MultiCall.runWithChecks.selector, callContracts, callDatas, callValues, checkContracts, checkValues
            ),
            false
        );

        deal(USDC, address(wallet), 400e6);
        wallet.executeQuarkOperation(
            multiCall,
            abi.encodeWithSelector(
                MultiCall.runWithChecks.selector, callContracts, callDatas, callValues, checkContracts, checkValues
            ),
            false
        );

        // Wallet no longer owe Comet, condition#2 will fail
        deal(USDC, address(wallet), 400e6);
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
                    checkValues[1],
                    abi.encodeWithSelector(CheckUint256Gt.CheckFailed.selector)
                )
            )
        );
        wallet.executeQuarkOperation(
            multiCall,
            abi.encodeWithSelector(
                MultiCall.runWithChecks.selector, callContracts, callDatas, callValues, checkContracts, checkValues
            ),
            false
        );

        // Wallet fully pays off debt
        assertEq(IComet(comet).borrowBalanceOf(address(wallet)), 0);
    }

    // Test #7: MultiCall test to use SupplyComet scripts to supply and borrow in one transaction
    function testApproveSupplyComet() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(address(this), codeJar);
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

        wallet.executeQuarkOperation(
            multiCall, abi.encodeWithSelector(MultiCall.run.selector, callContracts, callDatas, callValues), false
        );

        assertEq(IERC20(USDC).balanceOf(address(wallet)), 1000_000_000);
    }

    // Test #8: MultiCall to execute buy every Monday with custom scripts
    function testBuyEthEveryMonday() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(address(this), codeJar);
        bytes memory multiCall = new YulHelper().getDeployed(
            "MultiCall.sol/MultiCall.json"
        );
        // one time deploy EveryMondayTriggerCondition
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

        // It's not Monday yet, so revert
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

        wallet.executeQuarkOperation(
            multiCall, abi.encodeWithSelector(MultiCall.run.selector, callContracts, callDatas, callValues), true
        );

        // Warp to Monday
        vm.warp(block.timestamp / 1 weeks * 1 weeks + 4 days);
        wallet.executeQuarkOperation(
            multiCall, abi.encodeWithSelector(MultiCall.run.selector, callContracts, callDatas, callValues), true
        );

        // Last run just completed, need to wait 7 days to buy eth again
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
        wallet.executeQuarkOperation(
            multiCall, abi.encodeWithSelector(MultiCall.run.selector, callContracts, callDatas, callValues), false
        );

        // Warp to next Monday
        vm.warp(block.timestamp / 1 weeks * 1 weeks + 11 days + 6 hours); // Add additional 6 hours, simulate couple hours in the middle of the day
        wallet.executeQuarkOperation(
            multiCall, abi.encodeWithSelector(MultiCall.run.selector, callContracts, callDatas, callValues), false
        );

        // Successfully bought 2 times
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 8000e6);
    }

    // Test #9: MultiCall to execute buy every Monday with custom scripts and checks
    function testBuyEthEveryMondayWithChecks() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(address(this), codeJar);
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
        bytes[] memory checkValues = new bytes[](3);

        // Execute everyMondayTriggerCondition script
        callContracts[0] = isMonday;
        callDatas[0] = abi.encodeCall(IsMonday.isMonday, ());
        callValues[0] = 0 wei;
        checkContracts[0] = checkIsTrue;
        checkValues[0] = hex"";

        // Approve router to spend USDC
        callContracts[1] = USDC;
        callDatas[1] = abi.encodeCall(IERC20.approve, (router, 1000e6));
        callValues[1] = 0 wei;
        checkContracts[1] = checkIsTrue;
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
        checkContracts[2] = checkUint256Gte;
        checkValues[2] = abi.encode(uint256(1e17)); // At least 0.1ETH

        // It's not Monday yet, so revert
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
                    hex"",
                    abi.encodeWithSelector(CheckIsTrue.CheckFailed.selector)
                )
            )
        );
        wallet.executeQuarkOperation(
            multiCall,
            abi.encodeWithSelector(
                MultiCall.runWithChecks.selector, callContracts, callDatas, callValues, checkContracts, checkValues
            ),
            true
        );

        // Warp to Monday
        vm.warp(block.timestamp / 1 weeks * 1 weeks + 4 days);
        wallet.executeQuarkOperation(
            multiCall,
            abi.encodeWithSelector(
                MultiCall.runWithChecks.selector, callContracts, callDatas, callValues, checkContracts, checkValues
            ),
            true
        );

        // Warp to Tuesday
        vm.warp(block.timestamp / 1 weeks * 1 weeks + 5 days);
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
                    hex"",
                    abi.encodeWithSelector(CheckIsTrue.CheckFailed.selector)
                )
            )
        );
        wallet.executeQuarkOperation(
            multiCall,
            abi.encodeWithSelector(
                MultiCall.runWithChecks.selector, callContracts, callDatas, callValues, checkContracts, checkValues
            ),
            true
        );

        // Warp to next Monday
        vm.warp(block.timestamp / 1 weeks * 1 weeks + 11 days + 6 hours); // Add additional 6 hours, simulate couple hours in the middle of the day
        wallet.executeQuarkOperation(
            multiCall,
            abi.encodeWithSelector(
                MultiCall.runWithChecks.selector, callContracts, callDatas, callValues, checkContracts, checkValues
            ),
            true
        );

        // Successfully bought 2 times
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 8000e6);
    }
}
