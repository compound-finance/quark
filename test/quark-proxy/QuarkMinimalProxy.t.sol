// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkMinimalProxy} from "quark-proxy/src/QuarkMinimalProxy.sol";
import {QuarkNonceManager} from "quark-core/src/QuarkNonceManager.sol";
import {QuarkWallet, IHasSignerExecutor} from "quark-core/src/QuarkWallet.sol";

import {YulHelper} from "test/lib/YulHelper.sol";
import {SignatureHelper} from "test/lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "test/lib/QuarkOperationHelper.sol";

contract QuarkMinimalProxyTest is Test {
    CodeJar public codeJar;
    QuarkWallet public walletImplementation;
    QuarkNonceManager public nonceManager;

    uint256 alicePrivateKey = 0x8675309;
    address aliceAccount;
    QuarkMinimalProxy public aliceWalletProxy;

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to %s", address(codeJar));

        nonceManager = new QuarkNonceManager();
        console.log("QuarkNonceManager deployed to %s", address(nonceManager));

        walletImplementation = new QuarkWallet(codeJar, nonceManager);
        console.log("QuarkWallet implementation deployed to %s", address(walletImplementation));

        aliceAccount = vm.addr(alicePrivateKey);
        console.log("aliceAccount: %s", aliceAccount);

        aliceWalletProxy = new QuarkMinimalProxy(address(walletImplementation), aliceAccount, address(0xabc));
        console.log("aliceWalletProxy deployed to %s", address(aliceWalletProxy));
    }

    function testSignerExecutor() public {
        vm.expectRevert();
        IHasSignerExecutor(address(walletImplementation)).signer();

        vm.expectRevert();
        IHasSignerExecutor(address(walletImplementation)).executor();

        assertEq(aliceWalletProxy.signer(), aliceAccount);
        assertEq(aliceWalletProxy.executor(), address(0xabc));

        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory testScript = new YulHelper().getCode("QuarkMinimalProxy.t.sol/TestHarness.json");
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
