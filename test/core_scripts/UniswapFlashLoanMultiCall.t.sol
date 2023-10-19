// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";

import "./../../src/CodeJar.sol";
import "./../../src/QuarkWallet.sol";
import "./../../src/QuarkWalletFactory.sol";
import "./../../src/core_scripts/UniswapFlashLoanMultiCall.sol";
import "./../lib/YulHelper.sol";
import "./../lib/SignatureHelper.sol";
import "./../lib/Counter.sol";
import "./interfaces/ISwapRouter.sol";
import "./interfaces/IComet.sol";

contract UniswapFlashLoanMultiCallTest is Test {
    QuarkWalletFactory public factory;
    // For signature to QuarkWallet
    uint256 alicePK = 0xa11ce;
    address alice = vm.addr(alicePK);
    SignatureHelper public signatureHelper;
    // Comet address in mainnet
    address constant comet = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    // Router info on mainnet
    address constant router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    function setUp() public {
        factory = new QuarkWalletFactory();
        signatureHelper = new SignatureHelper();
    }

    // Test #1: Using flash loan change comet asset from one to another within Comet
    function testFlashLoanOnBorrowPosition() public {
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        bytes memory uniswapFlashLoanMultiCall = new YulHelper().getDeployed(
            "UniswapFlashLoanMultiCall.sol/UniswapFlashLoanMultiCall.json"
        );

        // Set up some funds for test
        deal(WETH, address(wallet), 100 ether);
        // Set up compound position via prank
        vm.startPrank(address(wallet));
        // Approve Comet to spend WETH
        IERC20(WETH).approve(comet, 100 ether);
        // Supply WETH to Comet
        IComet(comet).supply(WETH, 2 ether);
        // Withdraw USDC from Comet
        IComet(comet).withdraw(USDC, 1000e6);
        // Transfer all USDC out to null address so test wallet will need to use flashloan to pay off debt
        // Leave only 1 USDC to repay flash loan fee
        IERC20(USDC).transfer(address(123), 999e6);
        vm.stopPrank();

        // Test user can switch collateral from ETH to LINK via flashloan without allocating USDC to pay off debt
        // Math here is not perfect, as in Terminal scripts we should be able to compute and find more precise numbers to accomplish this type of action
        address[] memory callContracts = new address[](8);
        bytes[] memory callDatas = new bytes[](8);
        uint256[] memory callValues = new uint256[](8);
        address[] memory checkContracts = new address[](8);
        bytes4[] memory checkSelectors = new bytes4[](8);
        bytes[] memory checkValues = new bytes[](8);

        uint256 linkBalanceEst = 2e18 * IComet(comet).getPrice(IComet(comet).getAssetInfoByAddress(WETH).priceFeed)
            / IComet(comet).getPrice(IComet(comet).getAssetInfoByAddress(LINK).priceFeed)
        // Use 90% of price calculation to encounter to price slippage during swapping
        * 9 / 10;

        // Approve Comet to spend USDC
        callContracts[0] = address(USDC);
        callDatas[0] = abi.encodeCall(IERC20.approve, (comet, 1000e6));
        callValues[0] = 0 wei;

        // Use flashloan usdc to pay off comet debt (1000USDC)
        callContracts[1] = address(comet);
        callDatas[1] = abi.encodeCall(IComet.supply, (USDC, 1000e6));
        callValues[1] = 0 wei;

        // Withdraw all comet collateral (2 ETH)
        callContracts[2] = address(comet);
        callDatas[2] = abi.encodeCall(IComet.withdraw, (WETH, 2 ether));
        callValues[2] = 0 wei;

        // Approve router for WETH
        callContracts[3] = address(WETH);
        callDatas[3] = abi.encodeCall(IERC20.approve, (router, 2 ether));
        callValues[3] = 0 wei;

        // Swap 2 ETH to LINK via router
        callContracts[4] = address(router);
        callDatas[4] = abi.encodeCall(
            ISwapRouter.exactInputSingle,
            (
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: WETH,
                    tokenOut: LINK,
                    fee: 3000, // 0.3%
                    recipient: address(wallet),
                    deadline: block.timestamp,
                    amountIn: 2 ether,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            )
        );
        callValues[4] = 0 wei;

        // Approve LINK to Comet
        callContracts[5] = address(LINK);
        callDatas[5] = abi.encodeCall(IERC20.approve, (comet, type(uint256).max));
        callValues[5] = 0 wei;

        // Supply LINK back to Comet
        callContracts[6] = address(comet);
        callDatas[6] = abi.encodeCall(IComet.supply, (LINK, LinkBalanceEst));
        callValues[6] = 0 wei;

        // Withdraw 1000 USDC from Comet again to repay debt
        callContracts[7] = address(comet);
        callDatas[7] = abi.encodeCall(IComet.withdraw, (USDC, 1000e6));
        callValues[7] = 0 wei;

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: uniswapFlashLoanMultiCall,
            scriptCalldata: abi.encodeWithSelector(
                UniswapFlashLoanMultiCall.run.selector,
                UniswapFlashLoanMultiCall.UniswapFlashLoanMultiCallPayload({
                    token0: USDC,
                    token1: DAI,
                    fee: 100,
                    amount0: 1000e6,
                    amount1: 0,
                    callContracts: callContracts,
                    callDatas: callDatas,
                    callValues: callValues,
                    withChecks: false,
                    checkContracts: checkContracts,
                    checkSelectors: checkSelectors,
                    checkValues: checkValues
                })
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: true
        });
        (uint8 v, bytes32 r, bytes32 s) = signatureHelper.signOp(wallet, op, alicePK);
        wallet.executeQuarkOperation(op, v, r, s);

        // Verify that user now has no WETH collateral on Comet, but only LINK
        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 0);
        assertEq(IComet(comet).collateralBalanceOf(address(wallet), LINK), LinkBalanceEst);
        assertEq(IComet(comet).borrowBalanceOf(address(wallet)), 1000e6);
    }

    // Test #2: Invalid caller
    function testInvalidCallerFlashLoan() public {
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        bytes memory uniswapFlashLoanMultiCall = new YulHelper().getDeployed(
            "UniswapFlashLoanMultiCall.sol/UniswapFlashLoanMultiCall.json"
        );

        deal(WETH, address(wallet), 100 ether);
        deal(USDC, address(wallet), 1000e6);

        // Try to invoke callback directly, expect revert with invalid caller
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: uniswapFlashLoanMultiCall,
            scriptCalldata: abi.encodeWithSelector(
                UniswapFlashLoanMultiCall.uniswapV3FlashCallback.selector,
                1000e6,
                1000e6,
                abi.encode(
                    UniswapFlashLoanMultiCall.FlashLoanInput({
                        amount0: 1 ether,
                        amount1: 0,
                        poolKey: PoolAddress.getPoolKey(WETH, USDC, 500),
                        callContracts: new address[](3),
                        callDatas: new bytes[](3),
                        callValues: new uint256[](3),
                        withChecks: false,
                        checkContracts: new address[](3),
                        checkSelectors: new bytes4[](3),
                        checkValues: new bytes[](3)
                    })
                )
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: true
        });
        (uint8 v, bytes32 r, bytes32 s) = signatureHelper.signOp(wallet, op, alicePK);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector,
                abi.encodeWithSelector(UniswapFlashLoanMultiCall.InvalidCaller.selector)
            )
        );
        wallet.executeQuarkOperation(op, v, r, s);
    }

    // Test #3: Not enough to repay flash loan, the transaction shall fail and revert
    function testNotEnoughToRepayFlashLoan() public {
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        bytes memory uniswapFlashLoanMultiCall = new YulHelper().getDeployed(
            "UniswapFlashLoanMultiCall.sol/UniswapFlashLoanMultiCall.json"
        );

        address[] memory callContracts = new address[](1);
        bytes[] memory callDatas = new bytes[](1);
        uint256[] memory callValues = new uint256[](1);
        address[] memory checkContracts = new address[](1);
        bytes4[] memory checkSelectors = new bytes4[](1);
        bytes[] memory checkValues = new bytes[](1);

        // Send USDC to random address
        callContracts[0] = address(USDC);
        callDatas[0] = abi.encodeCall(IERC20.transfer, (address(1), 1000e6));
        callValues[0] = 0 wei;

        UniswapFlashLoanMultiCall.UniswapFlashLoanMultiCallPayload memory payload = UniswapFlashLoanMultiCall
            .UniswapFlashLoanMultiCallPayload({
            token0: USDC,
            token1: DAI,
            fee: 100,
            amount0: 1000e6,
            amount1: 0,
            callContracts: callContracts,
            callDatas: callDatas,
            callValues: callValues,
            withChecks: false,
            checkContracts: checkContracts,
            checkSelectors: checkSelectors,
            checkValues: checkValues
        });

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: uniswapFlashLoanMultiCall,
            scriptCalldata: abi.encodeWithSelector(UniswapFlashLoanMultiCall.run.selector, payload),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: true
        });
        (uint8 v, bytes32 r, bytes32 s) = signatureHelper.signOp(wallet, op, alicePK);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector,
                abi.encodeWithSignature("Error(string)", "ERC20: transfer amount exceeds balance")
            )
        );
        wallet.executeQuarkOperation(op, v, r, s);
    }
}
