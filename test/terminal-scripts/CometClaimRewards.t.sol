// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdMath.sol";

import {CodeJar} from "quark-core/src/CodeJar.sol";
import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";

import {QuarkWalletProxyFactory} from "quark-proxy/src/QuarkWalletProxyFactory.sol";

import {YulHelper} from "test/lib/YulHelper.sol";
import {SignatureHelper} from "test/lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "test/lib/QuarkOperationHelper.sol";

import {Counter} from "test/lib/Counter.sol";

import "terminal-scripts/src/TerminalScript.sol";

/**
 * Tests for claiming COMP rewards
 */
contract CometClaimRewardsTest is Test {
    QuarkWalletProxyFactory public factory;
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
        factory = new QuarkWalletProxyFactory(address(new QuarkWallet(new CodeJar(), new QuarkStateManager())));
    }

    function testClaimComp() public {
        vm.pauseGasMetering();
        QuarkWallet wallet = QuarkWallet(factory.create(alice, address(0)));
        bytes memory terminalScript = new YulHelper().getDeployed("TerminalScript.sol/CometClaimRewards.json");

        deal(USDC, address(wallet), 1_000_000e6);

        vm.startPrank(address(wallet));
        IERC20(USDC).approve(comet, 1_000_000e6);
        IComet(comet).supply(USDC, 1_000_000e6);
        vm.stopPrank();

        // Fastforward 180 days block to accrue COMP
        vm.warp(block.timestamp + 180 days);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            terminalScript,
            abi.encodeCall(CometClaimRewards.claim, (cometReward, comet, address(wallet))),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        assertEq(IERC20(COMP).balanceOf(address(wallet)), 0e6);
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);
        assertGt(IERC20(COMP).balanceOf(address(wallet)), 0e6);
    }
}
