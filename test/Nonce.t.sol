// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {CodeJar} from "../src/CodeJar.sol";
import {QuarkWallet} from "../src/QuarkWallet.sol";
import {QuarkStateManager} from "../src/QuarkStateManager.sol";

contract QuarkStateManagerHarness is QuarkStateManager {
    function setNonceExternal(uint256 nonce) external {
        // NOTE: intentionally violates invariant in the name of... testing
        activeNonce[msg.sender] = nonce;
        (uint256 bucket, uint256 setMask) = getBucket(nonce);
        nonces[msg.sender][bucket] |= setMask;
        activeNonce[msg.sender] = 0;
    }
}

contract NonceTest is Test {
    QuarkStateManagerHarness public stateManagerHarness;

    function setUp() public {
        stateManagerHarness = new QuarkStateManagerHarness();
        console.log("QuarkStateManagerHarness deployed to: %s", address(stateManagerHarness));
    }

    function testRevertsForInvalidNonce() public {
        vm.expectRevert();
        stateManagerHarness.isNonceSet(address(this), 0);
        // NOTE: this is only defense-in-depth -- if this case is triggered, an invariant has been violated because an invalid nonce was acquired
        vm.expectRevert();
        stateManagerHarness.setNonceExternal(0);
    }

    function testIsSet() public {
        // nonce is unset by default
        assertEq(stateManagerHarness.isNonceSet(address(this), 1), false);
        // it can be set
        stateManagerHarness.setNonceExternal(1);
        assertEq(stateManagerHarness.isNonceSet(address(this), 1), true);
    }

    function testNonLinearNonce() public {
        // nonce values are not incremental; you can use a random number as
        // long as it has not been set
        uint256 nonce = 1234567890;

        assertEq(stateManagerHarness.isNonceSet(address(this), nonce), false);

        stateManagerHarness.setNonceExternal(nonce);
        assertEq(stateManagerHarness.isNonceSet(address(this), nonce), true);
    }

    function testNextUnusedNonce() public {
        assertEq(stateManagerHarness.nextUnusedNonce(address(this)), 1);

        stateManagerHarness.setNonceExternal(1);
        assertEq(stateManagerHarness.nextUnusedNonce(address(this)), 2);

        stateManagerHarness.setNonceExternal(2);
        assertEq(stateManagerHarness.nextUnusedNonce(address(this)), 3);
    }
}
