// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkNonceManager} from "quark-core/src/QuarkNonceManager.sol";

import {QuarkWalletProxyFactory} from "quark-proxy/src/QuarkWalletProxyFactory.sol";

import {Ethcall} from "quark-core-scripts/src/Ethcall.sol";
import {Multicall} from "quark-core-scripts/src/Multicall.sol";
import {PoolAddress} from "quark-core-scripts/src/vendor/uniswap_v3_periphery/PoolAddress.sol";
import {UniswapFlashSwapExactOut} from "quark-core-scripts/src/UniswapFlashSwapExactOut.sol";

import {Counter} from "test/lib/Counter.sol";

import {YulHelper} from "test/lib/YulHelper.sol";
import {SignatureHelper} from "test/lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "test/lib/QuarkOperationHelper.sol";

import {IComet} from "test/quark-core-scripts/interfaces/IComet.sol";

contract UniswapFlashSwapExactOutTest is Test {
    QuarkWalletProxyFactory public factory;
    // For signature to QuarkWallet
    uint256 alicePrivateKey = 0xa11ce;
    address alice = vm.addr(alicePrivateKey);

    // Comet address in mainnet
    address constant comet = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    bytes multicall = new YulHelper().getCode("Multicall.sol/Multicall.json");
    bytes ethcall = new YulHelper().getCode("Ethcall.sol/Ethcall.json");
    bytes uniswapFlashSwapExactOut =
        new YulHelper().getCode("UniswapFlashSwapExactOut.sol/UniswapFlashSwapExactOut.json");
    address ethcallAddress;
    address multicallAddress;
    address uniswapFlashSwapExactOutAddress;

    function setUp() public {
        vm.createSelectFork(
            vm.envString("MAINNET_RPC_URL"),
            18429607 // 2023-10-25 13:24:00 PST
        );
        factory = new QuarkWalletProxyFactory(address(new QuarkWallet(new CodeJar(), new QuarkNonceManager())));
        ethcallAddress = QuarkWallet(payable(factory.walletImplementation())).codeJar().saveCode(ethcall);
        multicallAddress = QuarkWallet(payable(factory.walletImplementation())).codeJar().saveCode(multicall);
        uniswapFlashSwapExactOutAddress =
            QuarkWallet(payable(factory.walletImplementation())).codeJar().saveCode(uniswapFlashSwapExactOut);
    }

    function testUniswapFlashSwapExactOutLeverageComet() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        // Set up some funds for test
        deal(WETH, address(wallet), 10 ether);

        // User gets into a borrow position in comet and tries to use a flash swap to leverage up
        // They borrow 1 ETH worth of USDC from comet and purchase 1 ETH
        // Some computation is required to get the right number to pass into UniswapFlashSwapExactOut core scripts

        // Compose array of actions
        address[] memory callContracts = new address[](3);
        bytes[] memory callDatas = new bytes[](3);
        //  Use 1.2 multiplier to address price slippage and fee during swap
        uint256 borrowAmountOfUSDC =
            (IComet(comet).getPrice(IComet(comet).getAssetInfoByAddress(WETH).priceFeed) * 1e6 / 1e8) * 12 / 10;
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
            Ethcall.run.selector, comet, abi.encodeCall(IComet.withdraw, (USDC, borrowAmountOfUSDC)), 0
        );

        UniswapFlashSwapExactOut.UniswapFlashSwapExactOutPayload memory payload = UniswapFlashSwapExactOut
            .UniswapFlashSwapExactOutPayload({
            tokenOut: WETH,
            tokenIn: USDC,
            fee: 500,
            amountOut: 1 ether,
            sqrtPriceLimitX96: 0,
            callContract: multicallAddress,
            callData: abi.encodeWithSelector(Multicall.run.selector, callContracts, callDatas)
        });

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            uniswapFlashSwapExactOut,
            abi.encodeWithSelector(UniswapFlashSwapExactOut.run.selector, payload),
            ScriptType.ScriptAddress
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, signature);

        // Verify that user is now supplying 10 + 1 WETH
        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 11 ether);
        // Verify the user borrow balance on Comet
        assertEq(IComet(comet).borrowBalanceOf(address(wallet)), borrowAmountOfUSDC);
    }

    function testRevertsForSecondCallback() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        // Set up some funds for test
        deal(WETH, address(wallet), 10 ether);

        address[] memory callContracts = new address[](1);
        bytes[] memory callDatas = new bytes[](1);

        // Call into the wallet and try to execute the fallback function again using the callback mechanism
        callContracts[0] = address(wallet);
        callDatas[0] = abi.encodeWithSelector(
            Ethcall.run.selector,
            address(wallet),
            abi.encodeCall(UniswapFlashSwapExactOut.uniswapV3SwapCallback, (100, 500, bytes(""))),
            0
        );

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            uniswapFlashSwapExactOut,
            abi.encodeWithSelector(
                UniswapFlashSwapExactOut.run.selector,
                UniswapFlashSwapExactOut.UniswapFlashSwapExactOutPayload({
                    tokenOut: WETH,
                    tokenIn: USDC,
                    fee: 500,
                    amountOut: 1 ether,
                    sqrtPriceLimitX96: 0,
                    callContract: multicallAddress,
                    callData: abi.encodeWithSelector(Multicall.run.selector, callContracts, callDatas)
                })
            ),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        vm.resumeGasMetering();
        vm.expectRevert(
            abi.encodeWithSelector(
                Multicall.MulticallError.selector,
                0,
                callContracts[0],
                abi.encodeWithSelector(QuarkWallet.NoActiveCallback.selector)
            )
        );
        wallet.executeQuarkOperation(op, v, r, s);
    }

    function testInvalidCallerFlashSwap() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        deal(WETH, address(wallet), 100 ether);
        deal(USDC, address(wallet), 1000e6);

        // Try to invoke callback directly, expect revert with invalid caller
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            uniswapFlashSwapExactOut,
            abi.encodeWithSelector(
                UniswapFlashSwapExactOut.uniswapV3SwapCallback.selector,
                1000e6,
                1000e6,
                abi.encode(
                    UniswapFlashSwapExactOut.FlashSwapExactOutInput({
                        poolKey: PoolAddress.getPoolKey(WETH, USDC, 500),
                        callContract: address(0),
                        callData: hex""
                    })
                )
            ),
            ScriptType.ScriptAddress
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        vm.expectRevert(abi.encodeWithSelector(UniswapFlashSwapExactOut.InvalidCaller.selector));
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, signature);
    }

    function testNotEnoughToPayFlashSwap() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

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

        UniswapFlashSwapExactOut.UniswapFlashSwapExactOutPayload memory payload = UniswapFlashSwapExactOut
            .UniswapFlashSwapExactOutPayload({
            tokenOut: WETH,
            tokenIn: USDC,
            fee: 500,
            amountOut: 1 ether,
            sqrtPriceLimitX96: 0,
            callContract: multicallAddress,
            callData: abi.encodeWithSelector(Multicall.run.selector, callContracts, callDatas)
        });

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            uniswapFlashSwapExactOut,
            abi.encodeWithSelector(UniswapFlashSwapExactOut.run.selector, payload),
            ScriptType.ScriptAddress
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, signature);
    }

    function testRevertsIfCalledDirectly() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        UniswapFlashSwapExactOut.UniswapFlashSwapExactOutPayload memory payload = UniswapFlashSwapExactOut
            .UniswapFlashSwapExactOutPayload({
            tokenOut: WETH,
            tokenIn: USDC,
            fee: 500,
            amountOut: 1,
            sqrtPriceLimitX96: 0,
            callContract: address(0),
            callData: bytes("")
        });

        // gas: meter execute
        vm.resumeGasMetering();
        // Reverts when calling `allowCallback()`, which tries to get the `nonceManager` from self
        vm.expectRevert();
        UniswapFlashSwapExactOut(uniswapFlashSwapExactOutAddress).run(payload);
    }
}
