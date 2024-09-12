// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";
import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkWalletStandalone} from "quark-core/src/QuarkWalletStandalone.sol";

import {YulHelper} from "test/lib/YulHelper.sol";
import {SignatureHelper} from "test/lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "test/lib/QuarkOperationHelper.sol";

import {Logger} from "test/lib/Logger.sol";
import {Counter} from "test/lib/Counter.sol";
// import {MaxCounterScript} from "test/lib/MaxCounterScript.sol";

contract QuarkStateManagerTest is Test {
    CodeJar public codeJar;
    QuarkStateManager public stateManager;

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        stateManager = new QuarkStateManager();
        console.log("QuarkStateManager deployed to: %s", address(stateManager));
    }

    function testNonceZeroIsValid() public {
        // by default, nonce 0 is not set
        assertEq(stateManager.isNonceSet(address(0x123), 0), false);

        // nonce 0 can be set manually
        vm.prank(address(0x123));
        stateManager.claimNonce(0);
        assertEq(stateManager.isNonceSet(address(0x123), 0), true);
    }

    function testSetsAndGetsNextNonces() public {
        assertEq(stateManager.nextNonce(address(this)), 0);

        for (uint96 i = 0; i <= 550; i++) {
            stateManager.claimNonce(i);
        }

        assertEq(stateManager.nextNonce(address(this)), 551);

        for (uint96 i = 552; i <= 570; i++) {
            stateManager.claimNonce(i);
        }

        assertEq(stateManager.nextNonce(address(this)), 551);

        stateManager.claimNonce(551);

        assertEq(stateManager.nextNonce(address(this)), 571);
    }

    function testRevertsIfNonceIsAlreadySet() public {
        stateManager.claimNonce(0);

        vm.expectRevert(abi.encodeWithSelector(QuarkStateManager.NonceAlreadySet.selector));
        stateManager.claimNonce(0);
    }
}
