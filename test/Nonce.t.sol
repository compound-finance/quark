// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import { CodeJar } from "../src/CodeJar.sol";
import { QuarkWallet } from "../src/QuarkWallet.sol";

contract QuarkWalletHarness is QuarkWallet {
    constructor(address owner, CodeJar codeJar) QuarkWallet(owner, codeJar) { }

    function setNonceExternal(uint256 index) external {
        setNonce(index);
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
        walletHarness.setNonceExternal(0);
        assertEq(walletHarness.isSet(0), true);
    }

    function testNonLinearNonce() public {
        // nonce values are not incremental; you can use a random number as
        // long as it has not been set
        uint256 nonce = 1234567890;

        assertEq(walletHarness.isSet(nonce), false);

        walletHarness.setNonceExternal(nonce);
        assertEq(walletHarness.isSet(nonce), true);
    }

    function testNextUnusedNonce() public {
        assertEq(walletHarness.nextUnusedNonce(), 0);

        walletHarness.setNonceExternal(0);
        assertEq(walletHarness.nextUnusedNonce(), 1);

        walletHarness.setNonceExternal(1);
        assertEq(walletHarness.nextUnusedNonce(), 2);
    }
}
