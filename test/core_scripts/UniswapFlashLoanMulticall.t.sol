// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";

import "./../../src/CodeJar.sol";
import "./../../src/QuarkWallet.sol";
import "./../../src/core_scripts/interfaces/IComet.sol";
import "./../../src/core_scripts/interfaces/IERC20.sol";
import "./../../src/core_scripts/UniswapFlashLoanMulticall.sol";
import "./../lib/YulHelper.sol";
import "./../lib/Counter.sol";

contract UniswapFlashLoanMulticallTest is Test {
    CodeJar public codeJar;
    bytes32 internal constant QUARK_OPERATION_TYPEHASH =
        keccak256(
            "QuarkOperation(bytes scriptSource,bytes scriptCalldata,uint256 nonce,uint256 expiry)"
        );
    // Comet address in mainnet
    address constant comet = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address constant USDC =  0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    // Router info on mainnet
    address constant router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    function setUp() public {
        codeJar = new CodeJar();
        codeJar.saveCode(
            new YulHelper().getDeployed(
                "UniswapFlashLoanMulticall.sol/UniswapFlashLoanMulticall.json"
            )
        );
    }

    // Test #1: Using flash loan change comet asset from one to another within Comet
    function testFlashLoanOnBorrowPosition() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(address(this), codeJar);
        bytes memory uniswapFlashLoanMulticall = new YulHelper().getDeployed(
            "UniswapFlashLoanMulticall.sol/UniswapFlashLoanMulticall.json"
        );

        // Set up some funds for test
        deal(WETH, address(wallet), 100 ether);
        // Set up compound position via prank
        vm.startPrank(address(wallet));
        // Approve Comet to spend USDC
        IERC20(WETH).approve(comet, 100 ether);
        // Supply ETH to Comet
        IComet(comet).supply(WETH, 2 ether);
        // Withdraw USDC from Comet
        IComet(comet).withdraw(USDC, 1000e6);
        // Transfer all USDC out to null address so test wallet will need to use flashloan to pay off debt
        // Leave only 1 USDC to repay flash loan fee
        IERC20(USDC).transfer(address(123), 999e6);
        vm.stopPrank();

        // Test user can switch colalteral from ETH to LINK via flashloan without allocating USDC to pay off debt 
        // Math here is not perfect, as in Terminal scripts we should be able to comout with the more precised numbers to accomplish this type of actions
        address[] memory callContracts = new address[](8);
        bytes[] memory callCodes = new bytes[](8);
        bytes[] memory callDatas = new bytes[](8);
        uint256[] memory callValues = new uint256[](8);

        uint256 LinkBalanceEst = 
            2e18 * IComet(comet).getPrice(IComet(comet).getAssetInfoByAddress(WETH).priceFeed) / IComet(comet).getPrice(IComet(comet).getAssetInfoByAddress(LINK).priceFeed) 
            // Use 90% of price calculation to encounter to price slippage during swapping
            * 9 / 10;

        // Approve Comet to spend USDC
        callContracts[0] = address(USDC);
        callCodes[0] = hex"";
        callDatas[0] = abi.encodeCall(IERC20.approve, (comet, 1000e6));
        callValues[0] = 0 wei;

        // Use flashloan usdc to pay off comet debt (1000USDC)
        callContracts[1] = address(comet);
        callCodes[1] = hex"";
        callDatas[1] = abi.encodeCall(IComet.supply, (USDC, 1000e6));
        callValues[1] = 0 wei;

        // Withdraw all comet collateral (2ETH)
        callContracts[2] = address(comet);
        callCodes[2] = hex"";
        callDatas[2] = abi.encodeCall(IComet.withdraw,  (WETH, 2 ether));
        callValues[2] = 0 wei;

        // Approve router for ETH
        callContracts[3] = address(WETH);
        callCodes[3] = hex"";
        callDatas[3] = abi.encodeCall(IERC20.approve, (router, 2 ether));
        callValues[3] = 0 wei;

        // Swap 2ETH to LINK via router
        callContracts[4] = address(router);
        callCodes[4] = hex"";
        callDatas[4] = abi.encodeCall(ISwapRouter.exactInputSingle, (ISwapRouter.ExactInputSingleParams({
              tokenIn: WETH,
              tokenOut: LINK,
              fee: 3000, // 0.3%
              recipient: address(wallet),
              deadline: block.timestamp,
              amountIn: 2 ether,
              amountOutMinimum: 0,
              sqrtPriceLimitX96: 0
          })));
        callValues[4] = 0 wei;

        // Approve LINK to Comet
        callContracts[5] = address(LINK);
        callCodes[5] = hex"";
        callDatas[5] = abi.encodeCall(IERC20.approve, (comet, type(uint256).max));
        callValues[5] = 0 wei;

        // Supply LINK back to Comet
        callContracts[6] = address(comet);
        callCodes[6] = hex"";
        callDatas[6] = abi.encodeCall(IComet.supply, (LINK, LinkBalanceEst));
        callValues[6] = 0 wei;

        // Withdraw 1000 USDC from Comet again to repay debt
        callContracts[7] = address(comet);
        callCodes[7] = hex"";
        callDatas[7] = abi.encodeCall(IComet.withdraw,  (USDC, 1000e6));
        callValues[7] = 0 wei;

        UniswapFlashLoanMulticall.UniswapFlashLoanMulticallPayload memory payload = UniswapFlashLoanMulticall.UniswapFlashLoanMulticallPayload({
            token0: USDC,
            token1: DAI,
            fee: 100,
            amount0: 1000e6,
            amount1: 0,
            callContracts: callContracts,
            callCodes: callCodes,
            callDatas: callDatas,
            callValues: callValues
        });

        wallet.executeQuarkOperation(
            uniswapFlashLoanMulticall,
            abi.encodeWithSelector(
                UniswapFlashLoanMulticall.run.selector,
                payload
            ), 
            true
        );

        // Verify that user now has no ETH collateral on Comet, but only LINK
        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 0);
        assertEq(IComet(comet).collateralBalanceOf(address(wallet), LINK), LinkBalanceEst);
        assertEq(IComet(comet).borrowBalanceOf(address(wallet)), 1000e6);
    }
}

// Helper interfaces thats only used in test for swapping
interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}