// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdMath.sol";

import "./../../src/QuarkWallet.sol";
import "./../../src/QuarkWalletFactory.sol";
import "./../../src/terminal_scripts/TerminalScript.sol";
import "./../lib/YulHelper.sol";
import "./../lib/SignatureHelper.sol";
import "./../lib/Counter.sol";

/**
 * Scenario test for uesr to sell assetes from Uniswap V3
 */
contract SellAssetWithUSDCBasePair is Test {
    QuarkWalletFactory public factory;
    Counter public counter;
    uint256 alicePrivateKey = 0xa11ce;
    address alice = vm.addr(alicePrivateKey);

    // Contracts address on mainnet
    address constant comet = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    // Uniswap router info on mainnet
    address constant uniswapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    function setUp() public {
        // Fork setup
        vm.createSelectFork(
            string.concat(
                "https://node-provider.compound.finance/ethereum-mainnet/", vm.envString("NODE_PROVIDER_BYPASS_KEY")
            ),
            18429607 // 2023-10-25 13:24:00 PST
        );
        factory = new QuarkWalletFactory();
    }

    // Usually one stop is sufficient for pairs with high liquidity
    function testSellAssetOneStopTerminalScript() public {
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        bytes memory terminalScript = new YulHelper().getDeployed(
            "TerminalScript.sol/TerminalScript.json"
        );

        deal(WETH, address(wallet), 2 ether);

        // ExactIn: Limit the amount of USDC you want to spend and receive as much WETH as possible
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: terminalScript,
            scriptCalldata: abi.encodeWithSelector(
                TerminalScript.swapAssetExactIn.selector,
                uniswapRouter,
                WETH,
                1 ether,
                1000e6,
                abi.encodePacked(WETH, uint24(500), USDC) // Path: WETH - 0.05% -> USDC
            ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false,
            isReplayable: false,
            requirements: new uint256[](0)
        });

        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        wallet.executeQuarkOperation(op, v, r, s);

        uint256 wethBalance = IERC20(WETH).balanceOf(address(wallet));
        uint256 usdcBalance = IERC20(USDC).balanceOf(address(wallet));
        assertEq(wethBalance, 1 ether);
        assertGe(usdcBalance, 1000e6);

        // ExactOut: Limit the amount of WETH you want to receive and spend as much USDC as necessary
        QuarkWallet.QuarkOperation memory op2 = QuarkWallet.QuarkOperation({
            scriptSource: terminalScript,
            scriptCalldata: abi.encodeWithSelector(
                TerminalScript.swapAssetExactOut.selector,
                uniswapRouter,
                WETH,
                1600e6,
                1 ether,
                abi.encodePacked(USDC, uint24(500), WETH) // Path: USDC - 0.05% -> WETH
            ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false,
            isReplayable: false,
            requirements: new uint256[](0)
        });

        (uint8 v2, bytes32 r2, bytes32 s2) = new SignatureHelper().signOp(alicePrivateKey, wallet, op2);
        wallet.executeQuarkOperation(op2, v2, r2, s2);
        assertGe(IERC20(WETH).balanceOf(address(wallet)), 0);
        assertEq(IERC20(USDC).balanceOf(address(wallet)), usdcBalance + 1600e6);
    }

    // Lower liquidity asset may require to have two stops (COMP -> ETH -> USDC)
    function testSellAssetTwoStopsTerminalScript() public {
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        bytes memory terminalScript = new YulHelper().getDeployed(
            "TerminalScript.sol/TerminalScript.json"
        );

        deal(COMP, address(wallet), 100e18);

        // ExactIn: Limit the amount of USDC you want to spend and receive as much COMP as possible
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: terminalScript,
            scriptCalldata: abi.encodeWithSelector(
                TerminalScript.swapAssetExactIn.selector,
                uniswapRouter,
                COMP,
                50e18,
                1800e6,
                abi.encodePacked(COMP, uint24(3000), WETH, uint24(500), USDC) // Path: COMP - 0.05% -> WETH - 0.3% -> USDC
            ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false,
            isReplayable: false,
            requirements: new uint256[](0)
        });

        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        wallet.executeQuarkOperation(op, v, r, s);

        uint256 compBalance = IERC20(COMP).balanceOf(address(wallet));
        uint256 usdcBalance = IERC20(USDC).balanceOf(address(wallet));
        assertEq(compBalance, 50e18);
        assertGe(usdcBalance, 1800e6);

        // ExactOut: Limit the amount of COMP you want to receive and spend as much USDC as necessary
        QuarkWallet.QuarkOperation memory op2 = QuarkWallet.QuarkOperation({
            scriptSource: terminalScript,
            scriptCalldata: abi.encodeWithSelector(
                TerminalScript.swapAssetExactOut.selector,
                uniswapRouter,
                COMP,
                1500e6,
                50e18,
                abi.encodePacked(USDC, uint24(500), WETH, uint24(3000), COMP) // Path: USDC - 0.05% -> WETH - 0.3% -> COMP
            ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false,
            isReplayable: false,
            requirements: new uint256[](0)
        });

        (uint8 v2, bytes32 r2, bytes32 s2) = new SignatureHelper().signOp(alicePrivateKey, wallet, op2);
        wallet.executeQuarkOperation(op2, v2, r2, s2);
        assertGe(IERC20(COMP).balanceOf(address(wallet)), 0);
        assertEq(IERC20(USDC).balanceOf(address(wallet)), usdcBalance + 1500e6);
    }
}
