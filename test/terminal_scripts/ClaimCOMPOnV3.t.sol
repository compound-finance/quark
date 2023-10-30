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
 * Scenario test for uesr to claim COMP rewards
 */
contract ClaimCOMPOnV3 is Test {
    QuarkWalletFactory public factory;
    Counter public counter;
    uint256 alicePrivateKey = 0xa11ce;
    address alice = vm.addr(alicePrivateKey);

    // Contracts address on mainnet
    address constant comet = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address constant cometReward = 0x1B0e765F6224C21223AeA2af16c1C46E38885a40;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;

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

    function testClaimCompTerminalScript() public {
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        bytes memory terminalScript = new YulHelper().getDeployed(
            "TerminalScript.sol/TerminalScript.json"
        );

        deal(USDC, address(wallet), 1_000_000e6);

        vm.startPrank(address(wallet));
        IERC20(USDC).approve(comet, 1_000_000e6);
        IComet(comet).supply(USDC, 1_000_000e6);
        vm.stopPrank();

        // Fastforward 180 days block to accrue COMP
        vm.roll(185529607);
        vm.warp(block.timestamp + 180 days);

        assertEq(IERC20(COMP).balanceOf(address(wallet)), 0e6);
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: terminalScript,
            scriptCalldata: abi.encodeWithSelector(TerminalScript.claimCOMP.selector, cometReward, comet, address(wallet)),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false,
            isReplayable: false,
            requirements: new uint256[](0)
        });

        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        wallet.executeQuarkOperation(op, v, r, s);

        assertGt(IERC20(COMP).balanceOf(address(wallet)), 0e6);
    }
}
