// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";

import "./../../src/CodeJar.sol";
import "./../../src/core_scripts/Ethcall.sol";
import "./../../src/core_scripts/Multicall.sol";
import "./../../src/core_scripts/UniswapFlashLoan.sol";
import "./../../src/QuarkWallet.sol";
import "./../../src/QuarkWalletFactory.sol";
import "./../lib/YulHelper.sol";
import "./../lib/SignatureHelper.sol";
import "./../lib/Counter.sol";
import "./interfaces/ISwapRouter.sol";
import "./interfaces/IComet.sol";

import "../lib/QuarkOperationHelper.sol";

contract UniswapFlashLoanTest is Test {
    QuarkWalletFactory public factory;
    // For signature to QuarkWallet
    uint256 alicePrivateKey = 0xa11ce;
    address alice = vm.addr(alicePrivateKey);

    // Comet address in mainnet
    address constant comet = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    // Router info on mainnet
    address constant uniswapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    bytes multicall = new YulHelper().getDeployed(
            "Multicall.sol/Multicall.json"
        );
    bytes ethcall = new YulHelper().getDeployed(
            "Ethcall.sol/Ethcall.json"
        );
    bytes uniswapFlashLoan = new YulHelper().getDeployed(
            "UniswapFlashLoan.sol/UniswapFlashLoan.json"
        );
    address ethcallAddress;
    address multicallAddress;
    address uniswapFlashLoanAddress;

    function setUp() public {
        vm.createSelectFork(
            string.concat(
                "https://node-provider.compound.finance/ethereum-mainnet/", vm.envString("NODE_PROVIDER_BYPASS_KEY")
            )
        );
        factory = new QuarkWalletFactory();
        ethcallAddress = factory.codeJar().saveCode(ethcall);
        multicallAddress = factory.codeJar().saveCode(multicall);
        uniswapFlashLoanAddress = factory.codeJar().saveCode(uniswapFlashLoan);
    }

    function testFlashLoanForCollateralSwapOnCompound() public {
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));

        // Set up some funds for test
        deal(WETH, address(wallet), 100 ether);
        // Set up compound position via prank
        vm.startPrank(address(wallet));
        // Approve Comet to spend WETH
        IERC20(WETH).approve(comet, 100 ether);
        // Supply WETH to Comet
        IComet(comet).supply(WETH, 2 ether);
        // Withdraw USDC from Comet
        IComet(comet).withdraw(USDC, 1_000e6);
        // Transfer all USDC out to null address so test wallet will need to use flashloan to pay off debt
        // Leave only 1 USDC to repay flash loan fee
        IERC20(USDC).transfer(address(123), 999e6);
        vm.stopPrank();

        // Test user can switch collateral from WETH to LINK via flashloan without allocating USDC to pay off debt
        // Math here is not perfect. Terminal scripts should be able to compute more precise numbers
        address[] memory callContracts = new address[](8);
        bytes[] memory callDatas = new bytes[](8);

        // Use 90% of price calculation to account for price slippage during swapping
        uint256 linkBalanceEst = 2e18 * IComet(comet).getPrice(IComet(comet).getAssetInfoByAddress(WETH).priceFeed)
            / IComet(comet).getPrice(IComet(comet).getAssetInfoByAddress(LINK).priceFeed) * 9 / 10;

        // Approve Comet to spend USDC
        callContracts[0] = ethcallAddress;
        callDatas[0] =
            abi.encodeWithSelector(Ethcall.run.selector, USDC, abi.encodeCall(IERC20.approve, (comet, 1_000e6)), 0);

        // Use flashloan usdc to pay off comet debt (1000USDC)
        callContracts[1] = ethcallAddress;
        callDatas[1] =
            abi.encodeWithSelector(Ethcall.run.selector, comet, abi.encodeCall(IComet.supply, (USDC, 1_000e6)), 0);

        // Withdraw all comet collateral (2 WETH)
        callContracts[2] = ethcallAddress;
        callDatas[2] =
            abi.encodeWithSelector(Ethcall.run.selector, comet, abi.encodeCall(IComet.withdraw, (WETH, 2 ether)), 0);

        // Approve uniswapRouter for WETH
        callContracts[3] = ethcallAddress;
        callDatas[3] = abi.encodeWithSelector(
            Ethcall.run.selector, WETH, abi.encodeCall(IERC20.approve, (uniswapRouter, 2 ether)), 0
        );

        // Swap 2 WETH for LINK via uniswapRouter
        callContracts[4] = ethcallAddress;
        callDatas[4] = abi.encodeWithSelector(
            Ethcall.run.selector,
            uniswapRouter,
            abi.encodeCall(
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
            ),
            0 // value
        );

        // Approve Comet for LINK
        callContracts[5] = ethcallAddress;
        callDatas[5] = abi.encodeWithSelector(
            Ethcall.run.selector,
            LINK,
            abi.encodeCall(IERC20.approve, (comet, type(uint256).max)),
            0 // value
        );

        // Supply LINK back to Comet
        callContracts[6] = ethcallAddress;
        callDatas[6] = abi.encodeWithSelector(
            Ethcall.run.selector,
            comet,
            abi.encodeCall(IComet.supply, (LINK, linkBalanceEst)),
            0 // value
        );

        // Withdraw 1000 USDC from Comet again to repay debt
        callContracts[7] = ethcallAddress;
        callDatas[7] = abi.encodeWithSelector(
            Ethcall.run.selector,
            comet,
            abi.encodeCall(IComet.withdraw, (USDC, 1_000e6)),
            0 // value
        );

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            uniswapFlashLoan,
            abi.encodeWithSelector(
                UniswapFlashLoan.run.selector,
                UniswapFlashLoan.UniswapFlashLoanPayload({
                    token0: USDC,
                    token1: DAI,
                    fee: 100,
                    amount0: 1_000e6,
                    amount1: 0,
                    callContract: multicallAddress,
                    callData: abi.encodeWithSelector(Multicall.run.selector, callContracts, callDatas)
                })
            ),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        wallet.executeQuarkOperation(op, v, r, s);

        // Verify that user now has no WETH collateral on Comet, but only LINK
        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 0);
        assertEq(IComet(comet).collateralBalanceOf(address(wallet), LINK), linkBalanceEst);
        assertEq(IComet(comet).borrowBalanceOf(address(wallet)), 1_000e6);
    }

    function testRevertsForInvalidCaller() public {
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));

        deal(WETH, address(wallet), 100 ether);
        deal(USDC, address(wallet), 1_000e6);

        // Invoking the callback directly should revert as invalid caller
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            uniswapFlashLoan,
            abi.encodeWithSelector(
                UniswapFlashLoan.uniswapV3FlashCallback.selector,
                1_000e6,
                1_000e6,
                abi.encode(
                    UniswapFlashLoan.FlashLoanCallbackPayload({
                        amount0: 1 ether,
                        amount1: 0,
                        poolKey: PoolAddress.getPoolKey(WETH, USDC, 500),
                        callContract: address(0),
                        callData: hex""
                    })
                )
            ),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector, abi.encodeWithSelector(UniswapFlashLoan.InvalidCaller.selector)
            )
        );
        wallet.executeQuarkOperation(op, v, r, s);
    }

    function testRevertsForInsufficientFundsToRepayFlashLoan() public {
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));

        // Send USDC to random address
        UniswapFlashLoan.UniswapFlashLoanPayload memory payload = UniswapFlashLoan.UniswapFlashLoanPayload({
            token0: USDC,
            token1: DAI,
            fee: 100,
            amount0: 1_000e6,
            amount1: 0,
            callContract: ethcallAddress,
            callData: abi.encodeWithSelector(
                Ethcall.run.selector, USDC, abi.encodeCall(IERC20.transfer, (address(1), 1_000e6)), 0
                )
        });

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            uniswapFlashLoan,
            abi.encodeWithSelector(UniswapFlashLoan.run.selector, payload),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector,
                abi.encodeWithSignature("Error(string)", "ERC20: transfer amount exceeds balance")
            )
        );
        wallet.executeQuarkOperation(op, v, r, s);
    }

    function testTokensOrderInvariant() public {
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));

        deal(USDC, address(wallet), 10_000e6);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            uniswapFlashLoan,
            abi.encodeWithSelector(
                UniswapFlashLoan.run.selector,
                UniswapFlashLoan.UniswapFlashLoanPayload({
                    token0: USDC,
                    token1: DAI,
                    fee: 100,
                    amount0: 10_000e6,
                    amount1: 0,
                    callContract: ethcallAddress,
                    callData: abi.encodeWithSelector(
                        Ethcall.run.selector, USDC, abi.encodeCall(IERC20.approve, (comet, 1_000e6)), 0
                    )
                })
            ),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        wallet.executeQuarkOperation(op, v, r, s);

        // Lose 1 USDC to flash loan fee
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 9_999e6);

        QuarkWallet.QuarkOperation memory op2 = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            uniswapFlashLoan,
            abi.encodeWithSelector(
                UniswapFlashLoan.run.selector,
                UniswapFlashLoan.UniswapFlashLoanPayload({
                    token0: DAI,
                    token1: USDC,
                    fee: 100,
                    amount0: 0,
                    amount1: 10_000e6,
                    callContract: ethcallAddress,
                    callData: abi.encodeWithSelector(
                        Ethcall.run.selector, 
                        USDC, 
                        abi.encodeCall(IERC20.approve, (comet, 1_000e6)), 
                        0 // value
                    )
                })
            ),
            ScriptType.ScriptAddress
        );
        (uint8 v2, bytes32 r2, bytes32 s2) = new SignatureHelper().signOp(alicePrivateKey, wallet, op2);
        wallet.executeQuarkOperation(op2, v2, r2, s2);

        // Lose 1 USDC to flash loan fee
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 9_998e6);
    }
}
