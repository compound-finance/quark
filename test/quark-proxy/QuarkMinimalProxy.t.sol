// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkMinimalProxy} from "quark-proxy/src/QuarkMinimalProxy.sol";
import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";
import {QuarkWallet, HasSignerExecutor} from "quark-core/src/QuarkWallet.sol";

import {YulHelper} from "test/lib/YulHelper.sol";
import {SignatureHelper} from "test/lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "test/lib/QuarkOperationHelper.sol";

contract QuarkMinimalProxyTest is Test {
    CodeJar public codeJar;
    QuarkWallet public walletImplementation;
    QuarkStateManager public stateManager;

    uint256 alicePrivateKey = 0x8675309;
    address aliceAccount;
    QuarkMinimalProxy public aliceWalletProxy;

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to %s", address(codeJar));

        stateManager = new QuarkStateManager();
        console.log("QuarkStateManager deployed to %s", address(stateManager));

        walletImplementation = new QuarkWallet(codeJar, stateManager);
        console.log("QuarkWallet implementation deployed to %s", address(walletImplementation));

        aliceAccount = vm.addr(alicePrivateKey);
        console.log("aliceAccount: %s", aliceAccount);

        aliceWalletProxy = new QuarkMinimalProxy(address(walletImplementation), aliceAccount, address(0xabc));
        console.log("aliceWalletProxy deployed to %s", address(aliceWalletProxy));
    }

    function testSignerExecutor() public {
        vm.expectRevert();
        HasSignerExecutor(address(walletImplementation)).signer();

        vm.expectRevert();
        HasSignerExecutor(address(walletImplementation)).executor();

        assertEq(aliceWalletProxy.signer(), aliceAccount);
        assertEq(aliceWalletProxy.executor(), address(0xabc));

        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory testScript = new YulHelper().getDeployed("QuarkMinimalProxy.t.sol/TestHarness.json");
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            QuarkWallet(payable(aliceWalletProxy)),
            testScript,
            abi.encodeWithSignature("getSignerAndExecutor()"),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) =
            new SignatureHelper().signOp(alicePrivateKey, QuarkWallet(payable(aliceWalletProxy)), op);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = QuarkWallet(payable(aliceWalletProxy)).executeQuarkOperation(op, v, r, s);
        (address signer, address executor) = abi.decode(result, (address, address));
        assertEq(signer, aliceAccount);
        assertEq(executor, address(0xabc));
    }
}

import {QuarkScript} from "quark-core/src/QuarkScript.sol";

contract TestHarness is QuarkScript {
    function getSignerAndExecutor() public view returns (address, address) {
        return (signer(), executor());
    }
}
