// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";

import "./../../src/CodeJar.sol";
import "./../../src/core_scripts/Ethcall.sol";
import "./../../src/core_scripts/Multicall.sol";
import "./../../src/core_scripts/UniswapFlashSwap.sol";
import "./../../src/vendor/uniswap_v3_periphery/PoolAddress.sol";
import "./../../src/QuarkWallet.sol";
import "./../../src/QuarkWalletFactory.sol";
import "./../lib/YulHelper.sol";
import "./../lib/SignatureHelper.sol";
import "./../lib/Counter.sol";
import "./interfaces/IComet.sol";

import "../lib/QuarkOperationHelper.sol";

contract UniswapFlashSwapTest is Test {
    QuarkWalletFactory public factory;
    // For signature to QuarkWallet
    uint256 alicePrivateKey = 0xa11ce;
    address alice = vm.addr(alicePrivateKey);

    // Comet address in mainnet
    address constant comet = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    bytes multicall = new YulHelper().getDeployed(
            "Multicall.sol/Multicall.json"
        );
    bytes ethcall = new YulHelper().getDeployed(
            "Ethcall.sol/Ethcall.json"
        );
    bytes uniswapFlashSwap = new YulHelper().getDeployed(
            "UniswapFlashSwap.sol/UniswapFlashSwap.json"
        );
    address ethcallAddress;
    address multicallAddress;

    function setUp() public {
        vm.createSelectFork(
            string.concat(
                "https://node-provider.compound.finance/ethereum-mainnet/", vm.envString("NODE_PROVIDER_BYPASS_KEY")
            )
        );
        factory = new QuarkWalletFactory();
        ethcallAddress = factory.codeJar().saveCode(ethcall);
        multicallAddress = factory.codeJar().saveCode(multicall);
    }

    function testUniswapFlashSwapMulticallLeverageComet() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));

        // Set up some funds for test
        deal(WETH, address(wallet), 10 ether);

        // User has a borrow position in comet and tries to use a flash swap to leverage up
        // They borrow 1 ETH worth of USDC from comet and purchase 1 ETH
        // Some computation is required to get the right number to pass into UniswapFlashSwap core scripts

        // Compose array of actions
        address[] memory callContracts = new address[](3);
        bytes[] memory callDatas = new bytes[](3);

        // Approve Comet to spend WETH
        callContracts[0] = ethcallAddress;
        callDatas[0] =
            abi.encodeWithSelector(Ethcall.run.selector, WETH, abi.encodeCall(IERC20.approve, (comet, 100 ether)), 0);

        // Supply WETH to Comet
        callContracts[1] = ethcallAddress;
        // 10 original + 1 leveraged
        callDatas[1] =
            abi.encodeWithSelector(Ethcall.run.selector, comet, abi.encodeCall(IComet.supply, (WETH, 11 ether)), 0);

        // Withdraw 1 WETH worth of USDC from Comet
        callContracts[2] = ethcallAddress;
        callDatas[2] = abi.encodeWithSelector(
            Ethcall.run.selector,
            comet,
            abi.encodeCall(
                IComet.withdraw,
                (
                    USDC,
                    //  Use 1.2 multiplier to address price slippage and fee during swap
                    (IComet(comet).getPrice(IComet(comet).getAssetInfoByAddress(WETH).priceFeed) * 1e6 / 1e8) * 12 / 10
                )
            ),
            0
        );

        UniswapFlashSwap.UniswapFlashSwapMulticallPayload memory payload = UniswapFlashSwap
            .UniswapFlashSwapMulticallPayload({
            token0: WETH,
            token1: USDC,
            fee: 500,
            amount0: 1 ether,
            amount1: 0,
            sqrtPriceLimitX96: uint160(4295128739 + 1),
            callContract: multicallAddress,
            callData: abi.encodeWithSelector(Multicall.run.selector, callContracts, callDatas)
        });

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            uniswapFlashSwap,
             abi.encodeWithSelector(UniswapFlashSwap.run.selector, payload),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);

        // Verify that user is now supplying 10 + 1 WETH
        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 11 ether);
    }

    function testInvalidCallerFlashSwap() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));

        deal(WETH, address(wallet), 100 ether);
        deal(USDC, address(wallet), 1000e6);

        // Try to invoke callback directly, expect revert with invalid caller
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            uniswapFlashSwap,
            abi.encodeWithSelector(
                UniswapFlashSwap.uniswapV3SwapCallback.selector,
                1000e6,
                1000e6,
                abi.encode(
                    UniswapFlashSwap.FlashSwapMulticallInput({
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
                QuarkWallet.QuarkCallError.selector, abi.encodeWithSelector(UniswapFlashSwap.InvalidCaller.selector)
            )
        );
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
    }

    function testNotEnoughToPayFlashSwap() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));

        // Set up some funds for test
        deal(WETH, address(wallet), 10 ether);

        // Compose array of actions
        address[] memory callContracts = new address[](2);
        bytes[] memory callDatas = new bytes[](2);

        // Approve Comet to spend WETH
        callContracts[0] = ethcallAddress;
        callDatas[0] =
            abi.encodeWithSelector(Ethcall.run.selector, WETH, abi.encodeCall(IERC20.approve, (comet, 100 ether)), 0);

        // Supply WETH to Comet
        callContracts[1] = ethcallAddress;
        callDatas[1] =
            abi.encodeWithSelector(Ethcall.run.selector, comet, abi.encodeCall(IComet.supply, (WETH, 11 ether)), 0);

        UniswapFlashSwap.UniswapFlashSwapMulticallPayload memory payload = UniswapFlashSwap
            .UniswapFlashSwapMulticallPayload({
            token0: WETH,
            token1: USDC,
            fee: 500,
            amount0: 1 ether,
            amount1: 0,
            sqrtPriceLimitX96: uint160(4295128739 + 1),
            callContract: multicallAddress,
            callData: abi.encodeWithSelector(Multicall.run.selector, callContracts, callDatas)
        });

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            uniswapFlashSwap,
            abi.encodeWithSelector(UniswapFlashSwap.run.selector, payload),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector,
                abi.encodeWithSignature("Error(string)", "ERC20: transfer amount exceeds balance")
            )
        );
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
    }

    function testTokenOrderInvariant() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));

        // Start with 10000 USDC
        deal(USDC, address(wallet), 10000e6);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            uniswapFlashSwap,
            abi.encodeWithSelector(
                UniswapFlashSwap.run.selector,
                UniswapFlashSwap.UniswapFlashSwapMulticallPayload({
                    token0: WETH,
                    token1: USDC,
                    fee: 500,
                    amount0: 1 ether,
                    amount1: 0,
                    sqrtPriceLimitX96: uint160(4295128739 + 1),
                    callContract: ethcallAddress,
                    callData: abi.encodeWithSelector(
                        Ethcall.run.selector, address(USDC), abi.encodeCall(IERC20.approve, (comet, 1000e6)), 0
                        )
                })
            ),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        // Bought 1 weth for USDC
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 1 ether);

        vm.pauseGasMetering();
        // Payload swap token0 and token1 order, this will not affect the outcome
        QuarkWallet.QuarkOperation memory op2 = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            uniswapFlashSwap,
            abi.encodeWithSelector(
                UniswapFlashSwap.run.selector,
                UniswapFlashSwap.UniswapFlashSwapMulticallPayload({
                    token0: USDC,
                    token1: WETH,
                    fee: 500,
                    amount0: 0,
                    amount1: 1 ether,
                    sqrtPriceLimitX96: uint160(4295128739 + 1),
                    callContract: ethcallAddress,
                    callData: abi.encodeWithSelector(
                        Ethcall.run.selector, address(USDC), abi.encodeCall(IERC20.approve, (comet, 1000e6)), 0
                        )
                })
            ),
            ScriptType.ScriptAddress
        );
        (uint8 v2, bytes32 r2, bytes32 s2) = new SignatureHelper().signOp(alicePrivateKey, wallet, op2);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op2, v2, r2, s2);

        // Bought 1 weth for USDC
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 2 ether);
    }
}
