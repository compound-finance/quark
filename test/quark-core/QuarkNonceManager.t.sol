// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkNonceManager} from "quark-core/src/QuarkNonceManager.sol";
import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkWalletStandalone} from "quark-core/src/QuarkWalletStandalone.sol";

import {YulHelper} from "test/lib/YulHelper.sol";
import {SignatureHelper} from "test/lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "test/lib/QuarkOperationHelper.sol";

import {Logger} from "test/lib/Logger.sol";
import {Counter} from "test/lib/Counter.sol";
// import {MaxCounterScript} from "test/lib/MaxCounterScript.sol";

contract QuarkNonceManagerTest is Test {
    CodeJar public codeJar;
    QuarkNonceManager public nonceManager;

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        nonceManager = new QuarkNonceManager();
        console.log("QuarkNonceManager deployed to: %s", address(nonceManager));
    }

    function testNonceZeroIsValid() public {
        bytes32 nonce = bytes32(uint256(0));
        bytes32 EXHAUSTED = nonceManager.EXHAUSTED();

        // by default, nonce 0 is not set
        assertEq(nonceManager.getNonceSubmission(address(0x123), nonce), nonceManager.FREE());

        // nonce 0 can be set manually
        vm.prank(address(0x123));
        nonceManager.submitNonceToken(nonce, EXHAUSTED);
        assertEq(nonceManager.getNonceSubmission(address(0x123), nonce), nonceManager.EXHAUSTED());
    }

    // TODO: We should really replace this test with one that
    //       checks for a replay chain. We can check multiple nonces, but
    //       it's not strictly as interesting now.
    // function testSetsAndGetsNextNonces() public {
    //     assertEq(nonceManager.nextNonce(address(this)), 0);

    //     for (uint96 i = 0; i <= 550; i++) {
    //         nonceManager.claimNonce(i);
    //     }

    //     assertEq(nonceManager.nextNonce(address(this)), 551);

    //     for (uint96 i = 552; i <= 570; i++) {
    //         nonceManager.claimNonce(i);
    //     }

    //     assertEq(nonceManager.nextNonce(address(this)), 551);

    //     nonceManager.claimNonce(551);

    //     assertEq(nonceManager.nextNonce(address(this)), 571);
    // }

    function testRevertsIfNonceIsAlreadySet() public {
        bytes32 EXHAUSTED = nonceManager.EXHAUSTED();
        bytes32 nonce = bytes32(uint256(0));
        nonceManager.submitNonceToken(nonce, EXHAUSTED);

        vm.expectRevert(abi.encodeWithSelector(QuarkNonceManager.NonReplayableNonce.selector, address(this), nonce, bytes32(type(uint256).max)));
        nonceManager.submitNonceToken(nonce, EXHAUSTED);
    }
}
