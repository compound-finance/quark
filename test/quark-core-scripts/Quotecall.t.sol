// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";

import {QuarkWalletProxyFactory} from "quark-proxy/src/QuarkWalletProxyFactory.sol";

import {Ethcall} from "quark-core-scripts/src/Ethcall.sol";
import {Multicall} from "quark-core-scripts/src/Multicall.sol";
import {Quotecall} from "quark-core-scripts/src/Quotecall.sol";

import {Counter} from "test/lib/Counter.sol";
import {Reverts} from "test/lib/Reverts.sol";

import {YulHelper} from "test/lib/YulHelper.sol";
import {SignatureHelper} from "test/lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "test/lib/QuarkOperationHelper.sol";
import "quark-core-scripts/src/vendor/chainlink/AggregatorV3Interface.sol";

import {IComet, IERC20} from "test/lib/DeFiScripts.sol";

contract QuotecallTest is Test {
    event PayForGas(address indexed payer, address indexed payee, address indexed paymentToken, uint256 amount);

    QuarkWalletProxyFactory public factory;
    Counter public counter;
    uint256 alicePrivateKey = 0xa11ce;
    address alice = vm.addr(alicePrivateKey);
    CodeJar codeJar;

    // Comet address in mainnet
    address constant cUSDCv3 = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address constant cWETHv3 = 0xA17581A9E3356d9A858b789D68B4d866e593aE94;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    // Mainnet ETH / USD pricefeed
    address constant ETH_USD_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant ETH_BTC_PRICE_FEED = 0xAc559F25B1619171CbC396a50854A3240b6A4e99;

    // Uniswap router info on mainnet
    address constant uniswapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    bytes multicall = new YulHelper().getCode("Multicall.sol/Multicall.json");
    bytes ethcall = new YulHelper().getCode("Ethcall.sol/Ethcall.json");
    bytes reverts = new YulHelper().getCode("Reverts.sol/Reverts.json");

    // Quotecall has its contructor with 4 parameters
    uint256 constant MAX_DELTA_PERCENTAGE = 0.2e18; // 20%
    bytes quotecall;
    bytes quotecallUSDT;
    bytes quotecallWBTC;

    bytes legendCometSupplyScript = new YulHelper().getCode("DeFiScripts.sol/CometSupplyActions.json");

    bytes legendCometWithdrawScript = new YulHelper().getCode("DeFiScripts.sol/CometWithdrawActions.json");

    bytes legendUniswapSwapScript = new YulHelper().getCode("DeFiScripts.sol/UniswapSwapActions.json");

    address ethcallAddress;
    address multicallAddress;
    address revertsAddress;
    address quotecallAddress;
    address quotecallUSDTAddress;
    address quotecallWBTCAddress;
    address legendCometSupplyScriptAddress;
    address legendCometWithdrawScriptAddress;
    address legendUniswapSwapScriptAddress;

    function setUp() public {
        vm.createSelectFork(
            string.concat(
                "https://node-provider.compound.finance/ethereum-mainnet/", vm.envString("NODE_PROVIDER_BYPASS_KEY")
            ),
            18429607 // 2023-10-25 13:24:00 PST
        );
        factory = new QuarkWalletProxyFactory(address(new QuarkWallet(new CodeJar(), new QuarkStateManager())));
        counter = new Counter();
        counter.setNumber(0);

        codeJar = QuarkWallet(payable(factory.walletImplementation())).codeJar();
        ethcallAddress = codeJar.saveCode(ethcall);
        multicallAddress = codeJar.saveCode(multicall);
        revertsAddress = codeJar.saveCode(reverts);

        quotecall =
            abi.encodePacked(type(Quotecall).creationCode, abi.encode(ETH_USD_PRICE_FEED, USDC, MAX_DELTA_PERCENTAGE));
        quotecallUSDT =
            abi.encodePacked(type(Quotecall).creationCode, abi.encode(ETH_USD_PRICE_FEED, USDT, MAX_DELTA_PERCENTAGE));
        quotecallWBTC =
            abi.encodePacked(type(Quotecall).creationCode, abi.encode(ETH_BTC_PRICE_FEED, WBTC, MAX_DELTA_PERCENTAGE));

        quotecallAddress = codeJar.saveCode(quotecall);
        quotecallUSDTAddress = codeJar.saveCode(quotecallUSDT);
        quotecallWBTCAddress = codeJar.saveCode(quotecallWBTC);

        legendCometSupplyScriptAddress = codeJar.saveCode(legendCometSupplyScript);
        legendCometWithdrawScriptAddress = codeJar.saveCode(legendCometWithdrawScript);
        legendUniswapSwapScriptAddress = codeJar.saveCode(legendUniswapSwapScript);
    }

    /* ===== call context-based tests ===== */

    function testInitializeProperlyFromConstructor() public {
        address storedPriceFeedAddress = Quotecall(quotecallAddress).nativeTokenBasedPriceFeedAddress();
        address storedPaymentTokenAddress = Quotecall(quotecallAddress).paymentTokenAddress();
        uint256 storedMaxDeltaPercentage = Quotecall(quotecallAddress).maxDeltaPercentage();

        assertEq(storedPriceFeedAddress, ETH_USD_PRICE_FEED);
        assertEq(storedPaymentTokenAddress, USDC);
        assertEq(storedMaxDeltaPercentage, MAX_DELTA_PERCENTAGE);
    }

    function testRevertsForInvalidCallContext() public {
        Quotecall quotecallContract = Quotecall(quotecallAddress);
        // Direct calls fail when called directly
        vm.expectRevert(abi.encodeWithSelector(Quotecall.InvalidCallContext.selector));
        quotecallContract.run(
            ethcallAddress,
            abi.encodeWithSelector(
                Quotecall.run.selector,
                address(counter),
                abi.encodeCall(Counter.setNumber, (1)),
                0 // value
            ),
            10e6
        );
    }

    /* ===== general tests ===== */

    function testSimpleCounterAndPayWithUSDC() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        vm.txGasPrice(32 gwei);
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));
        // Give wallet some USDC for payment
        deal(USDC, address(wallet), 1000e6);

        // Compose array of parameters
        address[] memory callContracts = new address[](2);
        bytes[] memory callDatas = new bytes[](2);
        callContracts[0] = ethcallAddress;
        callDatas[0] = abi.encodeWithSelector(
            Ethcall.run.selector,
            address(counter),
            abi.encodeWithSignature("increment(uint256)", (20)),
            0 // value
        );
        callContracts[1] = ethcallAddress;
        callDatas[1] = abi.encodeWithSelector(
            Ethcall.run.selector,
            address(counter),
            abi.encodeWithSignature("decrement(uint256)", (5)),
            0 // value
        );
        assertEq(counter.number(), 0);

        // Execute through quotecall
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            quotecall,
            abi.encodeWithSelector(
                Quotecall.run.selector,
                multicallAddress,
                abi.encodeWithSelector(Multicall.run.selector, callContracts, callDatas),
                10e6
            ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectEmit(true, true, true, true);
        emit PayForGas(address(wallet), tx.origin, USDC, 10e6);
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(counter.number(), 15);
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 990e6);
    }

    function testSimpleTransferTokenAndPayWithUSDC() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        vm.txGasPrice(32 gwei);
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));
        // Give wallet some USDC for payment
        deal(USDC, address(wallet), 1000e6);

        // Execute through quotecall
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            quotecall,
            abi.encodeWithSelector(
                Quotecall.run.selector,
                ethcallAddress,
                abi.encodeWithSelector(
                    Ethcall.run.selector,
                    USDC,
                    abi.encodeWithSignature("transfer(address,uint256)", address(this), 10e6),
                    0
                ),
                10e6
            ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectEmit(true, true, true, true);
        emit PayForGas(address(wallet), tx.origin, USDC, 10e6);
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(IERC20(USDC).balanceOf(address(wallet)), 980e6);
        assertEq(IERC20(USDC).balanceOf(address(this)), 10e6);
    }

    function testReturnCallResult() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        vm.txGasPrice(32 gwei);
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        counter.setNumber(5);
        // Deal some USDC
        deal(USDC, address(wallet), 1000e6);
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            quotecall,
            abi.encodeWithSelector(
                Quotecall.run.selector,
                ethcallAddress,
                abi.encodeWithSelector(
                    Ethcall.run.selector, address(counter), abi.encodeWithSignature("decrement(uint256)", (1)), 0
                ),
                8e6
            ),
            ScriptType.ScriptSource
        );

        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory quarkReturn = wallet.executeQuarkOperation(op, v, r, s);
        bytes memory returnData = abi.decode(quarkReturn, (bytes));
        bytes memory returnData2 = abi.decode(returnData, (bytes));

        assertEq(counter.number(), 4);
        assertEq(abi.decode(returnData2, (uint256)), 4);
    }

    function testQuotecallForPayWithUSDT() public {
        vm.pauseGasMetering();
        vm.txGasPrice(32 gwei);
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        // Deal some USDT and WETH
        deal(USDT, address(wallet), 1000e6);
        deal(WETH, address(wallet), 1 ether);

        // Pay with USDT
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            quotecallUSDT,
            abi.encodeWithSelector(
                Quotecall.run.selector,
                ethcallAddress,
                abi.encodeWithSelector(
                    Ethcall.run.selector,
                    WETH,
                    abi.encodeWithSignature("transfer(address,uint256)", address(this), 1 ether),
                    0
                ),
                10e6
            ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        vm.resumeGasMetering();
        vm.expectEmit(true, true, true, true);
        emit PayForGas(address(wallet), tx.origin, USDT, 10e6);
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(IERC20(WETH).balanceOf(address(this)), 1 ether);
        // About $8 in USD fees
        assertEq(IERC20(USDT).balanceOf(address(wallet)), 990e6);
    }

    function testQuotecallForPayWithWBTC() public {
        vm.pauseGasMetering();
        vm.txGasPrice(32 gwei);
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        // Deal some WBTC and WETH
        deal(WBTC, address(wallet), 1e8);
        deal(WETH, address(wallet), 1 ether);

        // Pay with WBTC
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            quotecallWBTC,
            abi.encodeWithSelector(
                Quotecall.run.selector,
                ethcallAddress,
                abi.encodeWithSelector(
                    Ethcall.run.selector,
                    WETH,
                    abi.encodeWithSignature("transfer(address,uint256)", address(this), 1 ether),
                    0
                ),
                30e3
            ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        vm.resumeGasMetering();
        vm.expectEmit(true, true, true, true);
        emit PayForGas(address(wallet), tx.origin, WBTC, 30e3);
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(IERC20(WETH).balanceOf(address(this)), 1 ether);
        assertEq(IERC20(WBTC).balanceOf(address(wallet)), 99_970_000);
    }

    function testRevertsWhenQuoteTooLow() public {
        vm.pauseGasMetering();
        vm.txGasPrice(32 gwei);
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        // Deal some USDC and WETH
        deal(USDC, address(wallet), 1000e6);
        deal(WETH, address(wallet), 1 ether);

        // Pay with USDC
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            quotecall,
            abi.encodeWithSelector(
                Quotecall.run.selector,
                ethcallAddress,
                abi.encodeWithSelector(
                    Ethcall.run.selector,
                    WETH,
                    abi.encodeWithSignature("transfer(address,uint256)", address(this), 1 ether),
                    0
                ),
                2e6
            ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        vm.resumeGasMetering();
        vm.expectRevert(abi.encodeWithSelector(Quotecall.QuoteToleranceExceeded.selector));
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(IERC20(USDC).balanceOf(address(wallet)), 1000e6);
    }

    function testRevertsWhenQuoteTooHigh() public {
        vm.pauseGasMetering();
        vm.txGasPrice(32 gwei);
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        // Deal some USDC and WETH
        deal(USDC, address(wallet), 1000e6);
        deal(WETH, address(wallet), 1 ether);

        // Pay with USDC
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            quotecall,
            abi.encodeWithSelector(
                Quotecall.run.selector,
                ethcallAddress,
                abi.encodeWithSelector(
                    Ethcall.run.selector,
                    WETH,
                    abi.encodeWithSignature("transfer(address,uint256)", address(this), 1 ether),
                    0
                ),
                20e6
            ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        vm.resumeGasMetering();
        vm.expectRevert(abi.encodeWithSelector(Quotecall.QuoteToleranceExceeded.selector));
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(IERC20(USDC).balanceOf(address(wallet)), 1000e6);
    }

    function testQuotecallRevertsWhenCallReverts() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        vm.txGasPrice(32 gwei);
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));
        // Give wallet some USDC for payment
        deal(USDC, address(wallet), 1000e6);

        // Execute through quotecall
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            quotecall,
            abi.encodeWithSelector(Quotecall.run.selector, revertsAddress, "", 8e6),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert(abi.encodeWithSelector(Reverts.Whoops.selector));
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(IERC20(USDC).balanceOf(address(wallet)), 1000e6);
    }
}
