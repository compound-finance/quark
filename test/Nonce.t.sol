// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {CodeJar} from "../src/CodeJar.sol";
import {QuarkWallet} from "../src/QuarkWallet.sol";
import {QuarkStateManager} from "../src/QuarkStateManager.sol";

contract NonceTest is Test {
    QuarkStateManager public stateManager;

    function setUp() public {
        stateManager = new QuarkStateManager();
        console.log("QuarkStateManager deployed to: %s", address(stateManager));
    }

    function testRevertsForInvalidNonce() public {
        vm.expectRevert();
        stateManager.isNonceSet(address(this), 0);
        // NOTE: this is only defense-in-depth -- if this case is triggered, an invariant has been violated because an invalid nonce was acquired
        vm.expectRevert(QuarkStateManager.InvalidNonce.selector);
        stateManager.setNonce(0);
    }

    function testIsSet() public {
        // nonce is unset by default
        assertEq(stateManager.isNonceSet(address(this), 1), false);
        // it can be set
        stateManager.setNonce(1);
        assertEq(stateManager.isNonceSet(address(this), 1), true);
    }

    function testNonLinearNonce() public {
        // nonce values are not incremental; you can use a random number as
        // long as it has not been set
        uint96 nonce = 1_234_567_890;

        assertEq(stateManager.isNonceSet(address(this), nonce), false);

        stateManager.setNonce(nonce);
        assertEq(stateManager.isNonceSet(address(this), nonce), true);
    }

    function testNextUnusedNonce() public {
        uint96 nonce1 = stateManager.nextNonce(address(this));

        stateManager.setNonce(nonce1);
        assertEq(stateManager.nextNonce(address(this)), nonce1 + 1);

        stateManager.setNonce(nonce1 + 1);
        assertEq(stateManager.nextNonce(address(this)), nonce1 + 2);
    }
}
