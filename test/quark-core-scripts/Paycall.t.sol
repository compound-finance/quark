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
import {Paycall} from "quark-core-scripts/src/Paycall.sol";

import {Counter} from "test/lib/Counter.sol";

import {YulHelper} from "test/lib/YulHelper.sol";
import {SignatureHelper} from "test/lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "test/lib/QuarkOperationHelper.sol";
import "quark-core-scripts/src/vendor/chainlink/AggregatorV3Interface.sol";

import "legend-scripts/src/LegendScript.sol";

contract PaycallTest is Test {
    QuarkWalletProxyFactory public factory;
    Counter public counter;
    uint256 alicePrivateKey = 0xa11ce;
    address alice = vm.addr(alicePrivateKey);
    bytes32 constant CONTRACT_ADDRESS_SLOT = keccak256("quark.scripts.paycall.address.v1");
    CodeJar codeJar;

    // Comet address in mainnet
    address constant cUSDCv3 = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address constant cWETHv3 = 0xA17581A9E3356d9A858b789D68B4d866e593aE94;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    // Mainnet ETH / USD pricefeed
    address constant ETH_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant ETH_BTC_PRICE_FEED = 0xAc559F25B1619171CbC396a50854A3240b6A4e99;

    // Uniswap router info on mainnet
    address constant uniswapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    bytes multicall = new YulHelper().getCode("Multicall.sol/Multicall.json");
    bytes ethcall = new YulHelper().getCode("Ethcall.sol/Ethcall.json");
    // Paycall has its contructor with 2 parameters
    bytes paycall;

    bytes legendCometSupplyScript = new YulHelper().getCode("LegendScript.sol/CometSupplyActions.json");

    bytes legendCometWithdrawScript = new YulHelper().getCode("LegendScript.sol/CometWithdrawActions.json");

    bytes legendUniswapSwapScript = new YulHelper().getCode("LegendScript.sol/UniswapSwapActions.json");

    address ethcallAddress;
    address multicallAddress;
    address paycallAddress;
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
        paycall = abi.encodePacked(type(Paycall).creationCode, abi.encode(ETH_PRICE_FEED, USDC));

        paycallAddress = codeJar.saveCode(paycall);
        legendCometSupplyScriptAddress = codeJar.saveCode(legendCometSupplyScript);
        legendCometWithdrawScriptAddress = codeJar.saveCode(legendCometWithdrawScript);
        legendUniswapSwapScriptAddress = codeJar.saveCode(legendUniswapSwapScript);
    }

    /* ===== call context-based tests ===== */

    function testInitializesStorageProperlyFromConstructor() public {
        address storedPaycallAddress = address(uint160(uint256(vm.load(paycallAddress, CONTRACT_ADDRESS_SLOT))));
        assertEq(storedPaycallAddress, paycallAddress);
    }

    function testRevertsForInvalidCallContext() public {
        Paycall paycallContract = Paycall(paycallAddress);
        // Direct calls fail when called directly
        vm.expectRevert(abi.encodeWithSelector(Paycall.InvalidCallContext.selector));
        paycallContract.run(paycallAddress, ethcallAddress, abi.encodeWithSelector(
            Paycall.run.selector,
            address(counter),
            abi.encodeCall(Counter.setNumber, (1)),
            0 // value
        ));
    }

    function testCanBeGriefedByWritingAddressToQuarkWalletStorage() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            paycall,
            abi.encodeWithSelector(
                Paycall.run.selector, 
                paycallAddress,
                ethcallAddress, 
                abi.encodeWithSelector(
                    Ethcall.run.selector,
                    address(counter), abi.encode(Counter.setNumber.selector, 1),0 
                )
            ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // Override contract address to storage slot in Quark wallet
        vm.store(address(wallet), CONTRACT_ADDRESS_SLOT, bytes32(uint256(uint160(address(wallet)))));

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert(abi.encodeWithSelector(Multicall.InvalidCallContext.selector));
        wallet.executeQuarkOperation(op, v, r, s);
    }

    // // /* ===== general tests ===== */

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

        // Execute through paycall
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            paycall,
            abi.encodeWithSelector(Paycall.run.selector, paycallAddress, multicallAddress, abi.encodeWithSelector(Multicall.run.selector, callContracts, callDatas)),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertEq(counter.number(), 15);
        assertApproxEqAbs(IERC20(USDC).balanceOf(address(wallet)), 992e6, 1e6);
    }

    function testSimpleTransferTokenAndPayWithUSDC() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        vm.txGasPrice(32 gwei);
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));
        // Give wallet some USDC for payment
        deal(USDC, address(wallet), 1000e6);

        // Execute through paycall
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            paycall,
            abi.encodeWithSelector(Paycall.run.selector, paycallAddress, ethcallAddress, abi.encodeWithSelector(Ethcall.run.selector, USDC, abi.encodeWithSignature("transfer(address,uint256)", address(this), 10e6), 0)),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertApproxEqAbs(IERC20(USDC).balanceOf(address(wallet)), 982e6, 1e6);
        assertEq(IERC20(USDC).balanceOf(address(this)), 10e6);
    }

    function testSupplyWETHWithdrawUSDCOnCometAndPayWithUSDC() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        vm.txGasPrice(32 gwei);
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));
        // Set up some funds for test
        deal(WETH, address(wallet), 100 ether);

        // Compose array of parameters
        address[] memory callContracts = new address[](3);
        bytes[] memory callDatas = new bytes[](3);

        // Approve Comet to spend USDC
        callContracts[0] = ethcallAddress;
        callDatas[0] = abi.encodeWithSelector(
            Ethcall.run.selector,
            WETH,
            abi.encodeCall(IERC20.approve, (cUSDCv3, 100 ether)),
            0 // value
        );
        // Supply WETH to Comet
        callContracts[1] = ethcallAddress;
        callDatas[1] = abi.encodeWithSelector(
            Ethcall.run.selector,
            cUSDCv3,
            abi.encodeCall(IComet.supply, (WETH, 100 ether)),
            0 // value
        );
        // Withdraw USDC from Comet
        callContracts[2] = ethcallAddress;
        callDatas[2] = abi.encodeWithSelector(
            Ethcall.run.selector,
            cUSDCv3,
            abi.encodeCall(IComet.withdraw, (USDC, 1000e6)),
            0 // value
        );


        // Execute through paycall
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            paycall,
            abi.encodeWithSelector(Paycall.run.selector, paycallAddress, multicallAddress, abi.encodeWithSelector(Multicall.run.selector, callContracts, callDatas)),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertApproxEqAbs(IERC20(USDC).balanceOf(address(wallet)), 981e6, 1e6);
        assertEq(IComet(cUSDCv3).collateralBalanceOf(address(wallet), WETH), 100 ether);
        assertApproxEqAbs(IComet(cUSDCv3).borrowBalanceOf(address(wallet)), 1000e6, 2);
    }

    function testReturnCallResult() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        counter.setNumber(5);
        // Deal some USDC
        deal(USDC, address(wallet), 1000e6);
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            paycall,
            abi.encodeWithSelector(Paycall.run.selector, paycallAddress, ethcallAddress, abi.encodeWithSelector(
                Ethcall.run.selector, address(counter), abi.encodeWithSignature("decrement(uint256)", (1)), 0
            )),
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

    function testPaycallForPayWithOtherToken() public {
        vm.pauseGasMetering();
        vm.txGasPrice(32 gwei);
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));

        // Deploy a Paycall with USDT as payment token
        bytes memory paycallUSDT = abi.encodePacked(type(Paycall).creationCode, abi.encode(ETH_PRICE_FEED, USDT));
        address paycallUSDTAddress = codeJar.saveCode(paycallUSDT);
        // Deploy a Paycall with WBTC as payment token
        bytes memory paycallWBTC = abi.encodePacked(type(Paycall).creationCode, abi.encode(ETH_BTC_PRICE_FEED, WBTC));
        address paycallWBTCAddress = codeJar.saveCode(paycallWBTC);

        // Deal some USDT and WBTC
        deal(USDT, address(wallet), 1000e6);
        deal(WBTC, address(wallet), 1e8);
        deal(WETH, address(wallet), 2 ether);

        // Pay with USDT
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            paycallUSDT,
            abi.encodeWithSelector(Paycall.run.selector, paycallUSDTAddress, ethcallAddress, abi.encodeWithSelector(Ethcall.run.selector, WETH, abi.encodeWithSignature("transfer(address,uint256)", address(this), 1 ether), 0)),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        vm.pauseGasMetering();
        // Pay with WBTC
        QuarkWallet.QuarkOperation memory op2 = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            paycallWBTC,
            abi.encodeWithSelector(Paycall.run.selector, paycallWBTCAddress, ethcallAddress, abi.encodeWithSelector(Ethcall.run.selector, WETH, abi.encodeWithSignature("transfer(address,uint256)", address(this), 1 ether), 0)),
            ScriptType.ScriptSource
        );
        (uint8 v2, bytes32 r2, bytes32 s2) = new SignatureHelper().signOp(alicePrivateKey, wallet, op2);

        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op2, v2, r2, s2);
        assertEq(IERC20(WETH).balanceOf(address(this)), 2 ether);
        // About $8 in USD fees
        assertApproxEqAbs(IERC20(USDT).balanceOf(address(wallet)), 992e6, 1e6);
        // About $8 in USD fees in WBTC will be around 0.00017296 WBTC
        assertEq(IERC20(WBTC).balanceOf(address(wallet)), 99982704);
    }
}
