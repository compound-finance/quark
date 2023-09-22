// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import { CodeJar } from "../src/CodeJar.sol";
import { QuarkWallet } from "../src/QuarkWallet.sol";

contract QuarkWalletHarness is QuarkWallet {
    constructor(address owner, CodeJar codeJar) QuarkWallet(owner, codeJar) { }

    function setNonceExternal(uint256 index, bool value) external {
        setNonce(index, value);
    }
}

contract NonceTest is Test {
    QuarkWalletHarness public walletHarness;
    CodeJar public codeJar;

    address alice = address(10); // 0x00...a

    function setUp() public {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        walletHarness = new QuarkWalletHarness(alice, codeJar);
    }

    function testIsSet() public {
        // nonce is unset by default
        assertEq(walletHarness.isSet(0), false);

        // it can be set
        walletHarness.setNonceExternal(0, true);
        assertEq(walletHarness.isSet(0), true);

        // and unset
        walletHarness.setNonceExternal(0, false);
        assertEq(walletHarness.isSet(0), false);
    }

    function testNonLinearNonce() public {
        // nonce values are not incremental; you can use a random number and
        // use it as a nonce
        uint256 nonce = 1234567890;

        assertEq(walletHarness.isSet(nonce), false);

        walletHarness.setNonceExternal(nonce, true);
        assertEq(walletHarness.isSet(nonce), true);

        walletHarness.setNonceExternal(nonce, false);
        assertEq(walletHarness.isSet(nonce), false);
    }

    function testNextUnusedNonce() public {
        assertEq(walletHarness.nextUnusedNonce(), 0);

        walletHarness.setNonceExternal(0, true);
        assertEq(walletHarness.nextUnusedNonce(), 1);

        walletHarness.setNonceExternal(1, true);
        assertEq(walletHarness.nextUnusedNonce(), 2);
    }
}
