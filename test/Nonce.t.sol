// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {CodeJar} from "../src/CodeJar.sol";
import {QuarkWallet} from "../src/QuarkWallet.sol";
import {QuarkStorageManager} from "../src/QuarkStorageManager.sol";

contract QuarkStorageManagerHarness is QuarkStorageManager {
    function setNonceExternal(uint256 nonce) external {
        // NOTE: intentionally violates invariant in the name of... testing
        acquiredNonce[msg.sender] = nonce;
        (uint256 bucket, uint256 setMask) = locateNonce(nonce);
        nonces[msg.sender][bucket] |= setMask;
        acquiredNonce[msg.sender] = 0;
    }
}

contract NonceTest is Test {
    QuarkStorageManagerHarness public storageManagerHarness;

    function setUp() public {
        storageManagerHarness = new QuarkStorageManagerHarness();
        console.log("QuarkStorageManagerHarness deployed to: %s", address(storageManagerHarness));
    }

    function testRevertsForInvalidNonce() public {
        vm.expectRevert();
        storageManagerHarness.isNonceSet(address(this), 0);
        // NOTE: this is only defense-in-depth -- if this case is triggered, an invariant has been violated because an invalid nonce was acquired
        vm.expectRevert();
        storageManagerHarness.setNonceExternal(0);
    }

    function testIsSet() public {
        // nonce is unset by default
        assertEq(storageManagerHarness.isNonceSet(address(this), 1), false);
        // it can be set
        storageManagerHarness.setNonceExternal(1);
        assertEq(storageManagerHarness.isNonceSet(address(this), 1), true);
    }

    function testNonLinearNonce() public {
        // nonce values are not incremental; you can use a random number as
        // long as it has not been set
        uint256 nonce = 1234567890;

        assertEq(storageManagerHarness.isNonceSet(address(this), nonce), false);

        storageManagerHarness.setNonceExternal(nonce);
        assertEq(storageManagerHarness.isNonceSet(address(this), nonce), true);
    }

    function testNextUnusedNonce() public {
        assertEq(storageManagerHarness.nextUnusedNonce(address(this)), 1);

        storageManagerHarness.setNonceExternal(1);
        assertEq(storageManagerHarness.nextUnusedNonce(address(this)), 2);

        storageManagerHarness.setNonceExternal(2);
        assertEq(storageManagerHarness.nextUnusedNonce(address(this)), 3);
    }
}
