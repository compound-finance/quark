// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";

import "./../../src/CodeJar.sol";
import "./../../src/QuarkWallet.sol";
import "./../../src/core_scripts/UniswapFlashSwapMultiCall.sol";
import "./../../src/core_scripts/lib/PoolAddress.sol";
import "./../lib/YulHelper.sol";
import "./../lib/SignatureHelper.sol";
import "./../lib/Counter.sol";
import "./interfaces/IComet.sol";

contract UniswapFlashSwapMultiCallTest is Test {
    CodeJar public codeJar;
    // For signature to QuarkWallet
    address constant alice = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint256 constant alicePK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    SignatureHelper public signatureHelper;
    bytes32 internal constant QUARK_OPERATION_TYPEHASH =
        keccak256("QuarkOperation(bytes scriptSource,bytes scriptCalldata,uint256 nonce,uint256 expiry)");
    // Comet address in mainnet
    address constant cometAddr = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function setUp() public {
        codeJar = new CodeJar();
        signatureHelper = new SignatureHelper();

        codeJar.saveCode(
            new YulHelper().getDeployed(
                "UniswapFlashSwapMultiCall.sol/UniswapFlashSwapMultiCall.json"
            )
        );
    }

    // Test #1: Using flash swap to leverage/deleverage Comet position on single asset
    function testUniswapFlashSwapMultiCallLeverageComet() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(alice, codeJar);
        bytes memory uniswapFlashSwapMultiCall = new YulHelper().getDeployed(
            "UniswapFlashSwapMultiCall.sol/UniswapFlashSwapMultiCall.json"
        );

        // Set up some funds for test
        deal(WETH, address(wallet), 10 ether);

        // User has establish position in comet, try to use flash swap to leverage up
        // Borrow 1 ETH worth of USDC from comet, and purchase 1 ETH re-supply and remaining USDC back to Comet
        // Some computation is required to get the right number to pass into UniswapFlashSwapMultiCall core scripts

        // Compose array of actions
        address[] memory callContracts = new address[](3);
        bytes[] memory callDatas = new bytes[](3);
        uint256[] memory callValues = new uint256[](3);
        address[] memory checkContracts = new address[](3);
        bytes[] memory checkValues = new bytes[](3);

        // Approve Comet to spend WETH
        callContracts[0] = WETH;
        callDatas[0] = abi.encodeCall(IERC20.approve, (cometAddr, 100 ether));
        callValues[0] = 0 wei;

        // Supply ETH to Comet
        callContracts[1] = cometAddr;
        callDatas[1] = abi.encodeCall(IComet.supply, (WETH, 11 ether)); // 10 original + 1 leveraged
        callValues[1] = 0 wei;

        // Withdraw 1 ETH worth of USDC from Comet
        callContracts[2] = cometAddr;
        callDatas[2] = abi.encodeCall(
            IComet.withdraw,
            (
                USDC,
                (IComet(cometAddr).getPrice(IComet(cometAddr).getAssetInfoByAddress(WETH).priceFeed) * 1e6 / 1e8) * 12
                    / 10
            )
        ); //  Use 1.2 multiplier to address price slippage and fee during swap
        callValues[2] = 0 wei;

        UniswapFlashSwapMultiCall.UniswapFlashSwapMultiCallPayload memory payload = UniswapFlashSwapMultiCall
            .UniswapFlashSwapMultiCallPayload({
            token0: WETH,
            token1: USDC,
            fee: 500,
            amount0: 1 ether,
            amount1: 0,
            sqrtPriceLimitX96: uint160(4295128739 + 1),
            callContracts: callContracts,
            callDatas: callDatas,
            callValues: callValues,
            withChecks: false,
            checkContracts: checkContracts,
            checkValues: checkValues
        });

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: uniswapFlashSwapMultiCall,
            scriptCalldata: abi.encodeWithSelector(UniswapFlashSwapMultiCall.run.selector, payload),
            nonce: 0,
            expiry: type(uint256).max,
            allowCallback: true
        });
        (uint8 v, bytes32 r, bytes32 s) = signatureHelper.signOp(wallet, op, alicePK);
        wallet.executeQuarkOperation(op, v, r, s);

        // Verify that user is now holsing 10 + 1 ether exposure
        assertEq(IComet(cometAddr).collateralBalanceOf(address(wallet), WETH), 11 ether);
    }

    // Test #2: Invalid caller
    function testInvalidCallerFlashSwap() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(alice, codeJar);
        bytes memory uniswapFlashSwapMultiCall = new YulHelper().getDeployed(
            "UniswapFlashSwapMultiCall.sol/UniswapFlashSwapMultiCall.json"
        );

        deal(WETH, address(wallet), 100 ether);
        deal(USDC, address(wallet), 1000e6);

        // Try to invoke callback directly, expect revert with invalid caller
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: uniswapFlashSwapMultiCall,
            scriptCalldata: abi.encodeWithSelector(
                UniswapFlashSwapMultiCall.uniswapV3SwapCallback.selector,
                1000e6,
                1000e6,
                abi.encode(
                    UniswapFlashSwapMultiCall.FlashSwapMultiCallInput({
                        poolKey: PoolAddress.getPoolKey(WETH, USDC, 500),
                        callContracts: new address[](3),
                        callDatas: new bytes[](3),
                        callValues: new uint256[](3),
                        withChecks: false,
                        checkContracts: new address[](3),
                        checkValues: new bytes[](3)
                    })
                )
                ),
            nonce: 0,
            expiry: type(uint256).max,
            allowCallback: true
        });
        (uint8 v, bytes32 r, bytes32 s) = signatureHelper.signOp(wallet, op, alicePK);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector,
                abi.encodeWithSelector(UniswapFlashSwapMultiCall.InvalidCaller.selector)
            )
        );
        wallet.executeQuarkOperation(op, v, r, s);
    }

    // Test #3: flash swap revert if not paying back
    function testNotEnoughToPayFlashSwap() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(alice, codeJar);
        bytes memory uniswapFlashSwapMultiCall = new YulHelper().getDeployed(
            "UniswapFlashSwapMultiCall.sol/UniswapFlashSwapMultiCall.json"
        );

        // Set up some funds for test
        deal(WETH, address(wallet), 10 ether);

        // Compose array of actions
        address[] memory callContracts = new address[](2);
        bytes[] memory callDatas = new bytes[](2);
        uint256[] memory callValues = new uint256[](2);
        address[] memory checkContracts = new address[](2);
        bytes[] memory checkValues = new bytes[](2);

        // Approve Comet to spend WETH
        callContracts[0] = address(WETH);
        callDatas[0] = abi.encodeCall(IERC20.approve, (cometAddr, 100 ether));
        callValues[0] = 0 wei;

        // Supply ETH to Comet
        callContracts[1] = address(cometAddr);
        callDatas[1] = abi.encodeCall(IComet.supply, (WETH, 11 ether)); // 10 original + 1 leveraged
        callValues[1] = 0 wei;

        UniswapFlashSwapMultiCall.UniswapFlashSwapMultiCallPayload memory payload = UniswapFlashSwapMultiCall
            .UniswapFlashSwapMultiCallPayload({
            token0: WETH,
            token1: USDC,
            fee: 500,
            amount0: 1 ether,
            amount1: 0,
            sqrtPriceLimitX96: uint160(4295128739 + 1),
            callContracts: callContracts,
            callDatas: callDatas,
            callValues: callValues,
            withChecks: false,
            checkContracts: checkContracts,
            checkValues: checkValues
        });

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: uniswapFlashSwapMultiCall,
            scriptCalldata: abi.encodeWithSelector(UniswapFlashSwapMultiCall.run.selector, payload),
            nonce: 0,
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