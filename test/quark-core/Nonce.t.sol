// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";

contract NonceTest is Test {
    QuarkStateManager public stateManager;

    function setUp() public {
        stateManager = new QuarkStateManager();
        console.log("QuarkStateManager deployed to: %s", address(stateManager));
    }

    function testIsSet() public {
        // nonce is unset by default
        assertEq(stateManager.isNonceSet(address(this), 0), false);
        // it can be set
        stateManager.claimNonce(0);
        assertEq(stateManager.isNonceSet(address(this), 0), true);
    }

    function testNonLinearNonce() public {
        // nonce values are not incremental; you can use a random number as
        // long as it has not been set
        uint96 nonce = 1234567890;

        assertEq(stateManager.isNonceSet(address(this), nonce), false);

        stateManager.claimNonce(nonce);
        assertEq(stateManager.isNonceSet(address(this), nonce), true);
    }

    function testNextUnusedNonce() public {
        uint96 nonce1 = stateManager.nextNonce(address(this));

        stateManager.claimNonce(nonce1);
        assertEq(stateManager.nextNonce(address(this)), nonce1 + 1);

        stateManager.claimNonce(nonce1 + 1);
        assertEq(stateManager.nextNonce(address(this)), nonce1 + 2);
    }
}
