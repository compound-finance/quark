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
import "./../lib/Counter.sol";
import "./interfaces/IComet.sol";


contract UniswapFlashSwapMultiCallTest is Test {
    CodeJar public codeJar;
    bytes32 internal constant QUARK_OPERATION_TYPEHASH =
        keccak256(
            "QuarkOperation(bytes scriptSource,bytes scriptCalldata,uint256 nonce,uint256 expiry)"
        );
    // Comet address in mainnet
    address cometAddr = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address USDC =  0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function setUp() public {
        codeJar = new CodeJar();
        codeJar.saveCode(
            new YulHelper().getDeployed(
                "UniswapFlashSwapMultiCall.sol/UniswapFlashSwapMultiCall.json"
            )
        );
    }

    // Test #1: Using flash swap to leverage/deleverage Comet position on single asset
    function testUniswapFlashSwapMultiCallLeverageComet() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(address(this), codeJar);
        bytes memory uniswapFlashSwapMultiCall = new YulHelper().getDeployed(
            "UniswapFlashSwapMultiCall.sol/UniswapFlashSwapMultiCall.json"
        );

        // Set up some funds for test
        deal(WETH, address(wallet), 10 ether);

        // User has establish position in comet, try to use flash swap to leverage up
        // Borrow 1 ETH worth of USDC from comet, and purchase 1 ETH re-supply and remaining USDC back to Comet
        // Some computation is required to get the right number to pass into UniswapFlashSwapMultiCall core scripts
        AssetInfo memory ethAssetInfo = IComet(cometAddr).getAssetInfoByAddress(WETH);
        uint ethPrice = IComet(cometAddr).getPrice(ethAssetInfo.priceFeed) * 1e6 / 1e8; 

        // Compose array of actions
        address[] memory callContracts = new address[](3);
        bytes[] memory callCodes = new bytes[](3);
        bytes[] memory callDatas = new bytes[](3);
        uint256[] memory callValues = new uint256[](3);

        // Approve Comet to spend WETH
        callContracts[0] = address(WETH);
        callCodes[0] = hex"";
        callDatas[0] = abi.encodeCall(IERC20.approve, (cometAddr, 100 ether));
        callValues[0] = 0 wei;

        // Supply ETH to Comet
        callContracts[1] = address(cometAddr);
        callCodes[1] = hex"";
        callDatas[1] = abi.encodeCall(IComet.supply, (WETH, 11 ether)); // 10 original + 1 leveraged
        callValues[1] = 0 wei;

        // Withdraw 1 ETH worth of USDC from Comet
        callContracts[2] = address(cometAddr);
        callCodes[2] = hex"";
        callDatas[2] = abi.encodeCall(IComet.withdraw, (USDC, ethPrice * 12 / 10)); //  Use 1.2 multiplier to address price slippage and fee during swap
        callValues[2] = 0 wei;

        UniswapFlashSwapMultiCall.UniswapFlashSwapMultiCallPayload memory payload = UniswapFlashSwapMultiCall.UniswapFlashSwapMultiCallPayload({
            token0: WETH,
            token1: USDC,
            fee: 500,
            amount0: 1 ether,
            amount1: 0,
            sqrtPriceLimitX96: uint160(4295128739 + 1),
            callContracts: callContracts,
            callCodes: callCodes,
            callDatas: callDatas,
            callValues: callValues
        });

        wallet.executeQuarkOperation(
            uniswapFlashSwapMultiCall,
            abi.encodeWithSelector(
                UniswapFlashSwapMultiCall.run.selector,
                payload
            ), 
            true
        );

        // Verify that user is now holsing 10 + 1 ether exposure
        assertEq(IComet(cometAddr).collateralBalanceOf(address(wallet), WETH), 11 ether);
    }

    // Test #2: Invalid caller
    function testInvalidCallerFlashSwap() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(address(this), codeJar);
        bytes memory uniswapFlashSwapMultiCall = new YulHelper().getDeployed(
            "UniswapFlashSwapMultiCall.sol/UniswapFlashSwapMultiCall.json"
        );
        
        deal(WETH, address(wallet), 100 ether);
        deal(USDC, address(wallet), 1000e6);

        // Try to invoke callback directly, expect revert with invalid caller
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector,
                abi.encodeWithSelector(UniswapFlashSwapMultiCall.InvalidCaller.selector)
            )            
        );

        wallet.executeQuarkOperation(
            uniswapFlashSwapMultiCall,
            abi.encodeWithSelector(
                UniswapFlashSwapMultiCall.uniswapV3SwapCallback.selector,
                1000e6,
                1000e6,
                abi.encode(
                    UniswapFlashSwapMultiCall.FlashSwapMultiCallInput({
                        poolKey: PoolAddress.getPoolKey(
                            WETH,
                            USDC,
                            500
                        ),
                        callContracts: new address[](3),
                        callCodes: new bytes[](3),
                        callDatas: new bytes[](3),
                        callValues: new uint256[](3)
                    })
                )
            ), 
            true
        );
    }

    // Test #3: flash swap revert if not paying back
    function testNotEnoughToPayFlashSwap() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(address(this), codeJar);
        bytes memory uniswapFlashSwapMultiCall = new YulHelper().getDeployed(
            "UniswapFlashSwapMultiCall.sol/UniswapFlashSwapMultiCall.json"
        );

        // Set up some funds for test
        deal(WETH, address(wallet), 10 ether);

        // Compose array of actions
        address[] memory callContracts = new address[](2);
        bytes[] memory callCodes = new bytes[](2);
        bytes[] memory callDatas = new bytes[](2);
        uint256[] memory callValues = new uint256[](2);

        // Approve Comet to spend WETH
        callContracts[0] = address(WETH);
        callCodes[0] = hex"";
        callDatas[0] = abi.encodeCall(IERC20.approve, (cometAddr, 100 ether));
        callValues[0] = 0 wei;

        // Supply ETH to Comet
        callContracts[1] = address(cometAddr);
        callCodes[1] = hex"";
        callDatas[1] = abi.encodeCall(IComet.supply, (WETH, 11 ether)); // 10 original + 1 leveraged
        callValues[1] = 0 wei;

        UniswapFlashSwapMultiCall.UniswapFlashSwapMultiCallPayload memory payload = UniswapFlashSwapMultiCall.UniswapFlashSwapMultiCallPayload({
            token0: WETH,
            token1: USDC,
            fee: 500,
            amount0: 1 ether,
            amount1: 0,
            sqrtPriceLimitX96: uint160(4295128739 + 1),
            callContracts: callContracts,
            callCodes: callCodes,
            callDatas: callDatas,
            callValues: callValues
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector,
                abi.encodeWithSignature(
                    "Error(string)",
                    "ERC20: transfer amount exceeds balance"
                )
            )            
        );

        wallet.executeQuarkOperation(
            uniswapFlashSwapMultiCall,
            abi.encodeWithSelector(
                UniswapFlashSwapMultiCall.run.selector,
                payload
            ), 
            true
        );
    }
}