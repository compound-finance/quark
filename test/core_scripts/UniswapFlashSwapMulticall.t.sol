// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";

import "./../../src/CodeJar.sol";
import "./../../src/QuarkWallet.sol";
import "./../../src/QuarkWalletFactory.sol";
import "./../../src/core_scripts/UniswapFlashSwapMulticall.sol";
import "./../../src/core_scripts/lib/PoolAddress.sol";
import "./../lib/YulHelper.sol";
import "./../lib/SignatureHelper.sol";
import "./../lib/Counter.sol";
import "./interfaces/IComet.sol";

contract UniswapFlashSwapMulticallTest is Test {
    QuarkWalletFactory public factory;
    // For signature to QuarkWallet
    uint256 alicePrivateKey = 0xa11ce;
    address alice = vm.addr(alicePrivateKey);

    // Comet address in mainnet
    address constant comet = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function setUp() public {
        vm.createSelectFork(
            string.concat(
                "https://node-provider.compound.finance/ethereum-mainnet/", vm.envString("NODE_PROVIDER_BYPASS_KEY")
            )
        );
        factory = new QuarkWalletFactory();
    }

    function testUniswapFlashSwapMulticallLeverageComet() public {
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        bytes memory uniswapFlashSwapMulticall = new YulHelper().getDeployed(
            "UniswapFlashSwapMulticall.sol/UniswapFlashSwapMulticall.json"
        );

        // Set up some funds for test
        deal(WETH, address(wallet), 10 ether);

        // User has a borrow position in comet and tries to use a flash swap to leverage up
        // They borrow 1 ETH worth of USDC from comet and purchase 1 ETH
        // Some computation is required to get the right number to pass into UniswapFlashSwapMulticall core scripts

        // Compose array of actions
        address[] memory callContracts = new address[](3);
        bytes[] memory callDatas = new bytes[](3);
        uint256[] memory callValues = new uint256[](3);

        // Approve Comet to spend WETH
        callContracts[0] = WETH;
        callDatas[0] = abi.encodeCall(IERC20.approve, (comet, 100 ether));
        callValues[0] = 0 wei;

        // Supply WETH to Comet
        callContracts[1] = comet;
        callDatas[1] = abi.encodeCall(IComet.supply, (WETH, 11 ether)); // 10 original + 1 leveraged
        callValues[1] = 0 wei;

        // Withdraw 1 WETH worth of USDC from Comet
        callContracts[2] = comet;
        callDatas[2] = abi.encodeCall(
            IComet.withdraw,
            (USDC, (IComet(comet).getPrice(IComet(comet).getAssetInfoByAddress(WETH).priceFeed) * 1e6 / 1e8) * 12 / 10)
        ); //  Use 1.2 multiplier to address price slippage and fee during swap
        callValues[2] = 0 wei;

        UniswapFlashSwapMulticall.UniswapFlashSwapMulticallPayload memory payload = UniswapFlashSwapMulticall
            .UniswapFlashSwapMulticallPayload({
            token0: WETH,
            token1: USDC,
            fee: 500,
            amount0: 1 ether,
            amount1: 0,
            sqrtPriceLimitX96: uint160(4295128739 + 1),
            callContracts: callContracts,
            callDatas: callDatas,
            callValues: callValues
        });

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: uniswapFlashSwapMulticall,
            scriptCalldata: abi.encodeWithSelector(UniswapFlashSwapMulticall.run.selector, payload),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: true,
            isReplayable: false,
            requirements: new uint256[](0)
        });
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        wallet.executeQuarkOperation(op, v, r, s);

        // Verify that user is now supplying 10 + 1 WETH
        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 11 ether);
    }

    function testInvalidCallerFlashSwap() public {
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        bytes memory uniswapFlashSwapMulticall = new YulHelper().getDeployed(
            "UniswapFlashSwapMulticall.sol/UniswapFlashSwapMulticall.json"
        );

        deal(WETH, address(wallet), 100 ether);
        deal(USDC, address(wallet), 1000e6);

        // Try to invoke callback directly, expect revert with invalid caller
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: uniswapFlashSwapMulticall,
            scriptCalldata: abi.encodeWithSelector(
                UniswapFlashSwapMulticall.uniswapV3SwapCallback.selector,
                1000e6,
                1000e6,
                abi.encode(
                    UniswapFlashSwapMulticall.FlashSwapMulticallInput({
                        poolKey: PoolAddress.getPoolKey(WETH, USDC, 500),
                        callContracts: new address[](3),
                        callDatas: new bytes[](3),
                        callValues: new uint256[](3)
                    })
                )
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: true,
            isReplayable: false,
            requirements: new uint256[](0)
        });
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector,
                abi.encodeWithSelector(UniswapFlashSwapMulticall.InvalidCaller.selector)
            )
        );
        wallet.executeQuarkOperation(op, v, r, s);
    }

    function testNotEnoughToPayFlashSwap() public {
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        bytes memory uniswapFlashSwapMulticall = new YulHelper().getDeployed(
            "UniswapFlashSwapMulticall.sol/UniswapFlashSwapMulticall.json"
        );

        // Set up some funds for test
        deal(WETH, address(wallet), 10 ether);

        // Compose array of actions
        address[] memory callContracts = new address[](2);
        bytes[] memory callDatas = new bytes[](2);
        uint256[] memory callValues = new uint256[](2);

        // Approve Comet to spend WETH
        callContracts[0] = WETH;
        callDatas[0] = abi.encodeCall(IERC20.approve, (comet, 100 ether));
        callValues[0] = 0 wei;

        // Supply WETH to Comet
        callContracts[1] = comet;
        callDatas[1] = abi.encodeCall(IComet.supply, (WETH, 11 ether)); // 10 original + 1 leveraged
        callValues[1] = 0 wei;

        UniswapFlashSwapMulticall.UniswapFlashSwapMulticallPayload memory payload = UniswapFlashSwapMulticall
            .UniswapFlashSwapMulticallPayload({
            token0: WETH,
            token1: USDC,
            fee: 500,
            amount0: 1 ether,
            amount1: 0,
            sqrtPriceLimitX96: uint160(4295128739 + 1),
            callContracts: callContracts,
            callDatas: callDatas,
            callValues: callValues
        });

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: uniswapFlashSwapMulticall,
            scriptCalldata: abi.encodeWithSelector(UniswapFlashSwapMulticall.run.selector, payload),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: true,
            isReplayable: false,
            requirements: new uint256[](0)
        });
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector,
                abi.encodeWithSignature("Error(string)", "ERC20: transfer amount exceeds balance")
            )
        );
        wallet.executeQuarkOperation(op, v, r, s);
    }

    function testMulticallError() public {
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        bytes memory uniswapFlashSwapMulticall = new YulHelper().getDeployed(
            "UniswapFlashSwapMulticall.sol/UniswapFlashSwapMulticall.json"
        );

        address[] memory callContracts = new address[](2);
        bytes[] memory callDatas = new bytes[](2);
        uint256[] memory callValues = new uint256[](2);

        callContracts[0] = WETH;
        callDatas[0] = abi.encodeCall(IERC20.approve, (comet, 100 ether));
        callValues[0] = 0 wei;

        // Send 1000 USDC, this will fail with insufficient balance
        callContracts[1] = USDC;
        callDatas[1] = abi.encodeCall(IERC20.transfer, (address(123), 1000e6));
        callValues[1] = 0 wei;

        UniswapFlashSwapMulticall.UniswapFlashSwapMulticallPayload memory payload = UniswapFlashSwapMulticall
            .UniswapFlashSwapMulticallPayload({
            token0: WETH,
            token1: USDC,
            fee: 500,
            amount0: 1 ether,
            amount1: 0,
            sqrtPriceLimitX96: uint160(4295128739 + 1),
            callContracts: callContracts,
            callDatas: callDatas,
            callValues: callValues
        });

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: uniswapFlashSwapMulticall,
            scriptCalldata: abi.encodeWithSelector(UniswapFlashSwapMulticall.run.selector, payload),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: true,
            isReplayable: false,
            requirements: new uint256[](0)
        });
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector,
                abi.encodeWithSelector(
                    UniswapFlashSwapMulticall.MulticallError.selector,
                    1,
                    callContracts[1],
                    abi.encodeWithSignature("Error(string)", "ERC20: transfer amount exceeds balance")
                )
            )
        );
        wallet.executeQuarkOperation(op, v, r, s);
    }

    function testInvalidInput() public {
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        bytes memory uniswapFlashSwapMulticall = new YulHelper().getDeployed(
            "UniswapFlashSwapMulticall.sol/UniswapFlashSwapMulticall.json"
        );

        address[] memory callContracts = new address[](2);
        bytes[] memory callDatas = new bytes[](1);
        uint256[] memory callValues = new uint256[](1);

        callContracts[0] = address(USDC);
        callDatas[0] = abi.encodeCall(IERC20.transfer, (address(1), 1000e6));
        callValues[0] = 0 wei;

        callContracts[1] = address(USDC);

        UniswapFlashSwapMulticall.UniswapFlashSwapMulticallPayload memory payload = UniswapFlashSwapMulticall
            .UniswapFlashSwapMulticallPayload({
            token0: WETH,
            token1: USDC,
            fee: 500,
            amount0: 1 ether,
            amount1: 0,
            sqrtPriceLimitX96: uint160(4295128739 + 1),
            callContracts: callContracts,
            callDatas: callDatas,
            callValues: callValues
        });

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: uniswapFlashSwapMulticall,
            scriptCalldata: abi.encodeWithSelector(UniswapFlashSwapMulticall.run.selector, payload),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: true,
            isReplayable: false,
            requirements: new uint256[](0)
        });
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector,
                abi.encodeWithSelector(UniswapFlashSwapMulticall.InvalidInput.selector)
            )
        );
        wallet.executeQuarkOperation(op, v, r, s);
    }
}
