// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "quark-core/src/CodeJar.sol";
import "quark-core/src/QuarkWallet.sol";
import "quark-core/src/QuarkStateManager.sol";

import "quark-core-scripts/src/Ethcall.sol";

import "quark-proxy/src/QuarkMinimalProxy.sol";

import "test/lib/Logger.sol";
import "test/lib/Counter.sol";
import "test/lib/Reverts.sol";
import "test/lib/YulHelper.sol";
import "test/lib/Incrementer.sol";
import "test/lib/SignatureHelper.sol";
import "test/lib/PrecompileCaller.sol";
import "test/lib/MaxCounterScript.sol";
import "test/lib/GetMessageDetails.sol";
import "test/lib/CancelOtherScript.sol";
import "test/lib/QuarkOperationHelper.sol";

import "test/lib/AbstractQuarkWalletTest.sol";

contract QuarkWalletTest is AbstractQuarkWalletTest {
    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));

        stateManager = new QuarkStateManager();
        console.log("QuarkStateManager deployed to: %s", address(stateManager));

        aliceWallet = new QuarkWallet(aliceAccount, address(0), codeJar, stateManager);
        console.log("Alice signer: %s", aliceAccount);
        console.log("Alice wallet at: %s", address(aliceWallet));
    }
}

contract QuarkWalletProxyTest is AbstractQuarkWalletTest {
    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));

        stateManager = new QuarkStateManager();
        console.log("QuarkStateManager deployed to: %s", address(stateManager));

        QuarkWallet implementation = new QuarkWallet(address(0), address(0), codeJar, stateManager);
        aliceWallet = QuarkWallet(payable(address(new QuarkMinimalProxy(address(implementation), aliceAccount, address(0)))));
        console.log("Alice signer: %s", aliceAccount);
        console.log("Alice wallet proxy at: %s", address(aliceWallet));
    }
}
