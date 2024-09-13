// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {YulHelper} from "test/lib/YulHelper.sol";
import {SignatureHelper} from "test/lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "test/lib/QuarkOperationHelper.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkScript} from "quark-core/src/QuarkScript.sol";
import {QuarkNonceManager} from "quark-core/src/QuarkNonceManager.sol";
import {QuarkWallet, QuarkWalletMetadata} from "quark-core/src/QuarkWallet.sol";
import {QuarkWalletStandalone} from "quark-core/src/QuarkWalletStandalone.sol";
import {IHasSignerExecutor} from "quark-core/src/interfaces/IHasSignerExecutor.sol";

import {QuarkMinimalProxy} from "quark-proxy/src/QuarkMinimalProxy.sol";

import {BatchSend} from "test/lib/BatchCallback.sol";

contract BatchCallbackTest is Test {
    enum ExecutionType {
        Signature,
        Direct
    }

    CodeJar public codeJar;
    QuarkNonceManager public nonceManager;
    QuarkWallet public walletImplementation;

    uint256 alicePrivateKey = 0x8675309;
    address aliceAccount = vm.addr(alicePrivateKey);
    QuarkWallet aliceWallet; // see constructor()

    uint256 bobPrivateKey = 0x8675309;
    address bobAccount = vm.addr(bobPrivateKey);
    QuarkWallet bobWallet; // see constructor()

    bytes32 constant EXHAUSTED_TOKEN = bytes32(type(uint256).max);

    // wallet proxy instantiation helper
    function newWallet(address signer, address executor) internal returns (QuarkWallet) {
        return QuarkWallet(payable(new QuarkMinimalProxy(address(walletImplementation), signer, executor)));
    }

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        nonceManager = new QuarkNonceManager();
        console.log("QuarkNonceManager deployed to: %s", address(nonceManager));

        walletImplementation = new QuarkWallet(codeJar, nonceManager);
        console.log("QuarkWallet implementation: %s", address(walletImplementation));

        aliceWallet = newWallet(aliceAccount, address(0));
        console.log("Alice signer: %s", aliceAccount);
        console.log("Alice wallet at: %s", address(aliceWallet));

        bobWallet = newWallet(bobAccount, address(0));
        console.log("Bob signer: %s", bobAccount);
        console.log("Bob wallet at: %s", address(bobWallet));
    }

    /**
     * get active nonce, submission token, replay count ***************************
     *
     * single
     */
    function testBatchCallWithCallback() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory incrementByCallbackScript = new YulHelper().getCode("BatchCallback.sol/IncrementByCallback.json");
        QuarkWallet.QuarkOperation memory op1 = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet, incrementByCallbackScript, abi.encodeWithSignature("run()"), ScriptType.ScriptSource
        );
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op1);

        bytes memory callIncrementScript = new YulHelper().getCode("BatchCallback.sol/CallIncrement.json");
        QuarkWallet.QuarkOperation memory op2 = new QuarkOperationHelper().newBasicOpWithCalldata(
            bobWallet, callIncrementScript, abi.encodeWithSignature("run(address)", address(bobWallet)), ScriptType.ScriptSource
        );
        (uint8 v2, bytes32 r2, bytes32 s2) = new SignatureHelper().signOp(bobPrivateKey, bobWallet, op2);

        // gas: meter execute
        vm.resumeGasMetering();
        uint256 res = new BatchSend().submitTwo(
            aliceWallet,
            op1,
            v1,
            r1,
            s1,
            bobWallet,
            op2,
            v2,
            r2,
            s2
            );
        assertEq(res, 55);
    }
}
