pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/console.sol";

import {Test} from "forge-std/Test.sol";
import {QuarkWallet} from "../src/QuarkWallet.sol";
import {CodeJar} from "../src/CodeJar.sol";
import {Counter} from "./lib/Counter.sol";
import {YulHelper} from "./lib/YulHelper.sol";
import {QuarkStateManager} from "../src/QuarkStateManager.sol";
import {ExecuteOtherOperation} from "./lib/ExecuteOtherOperation.sol";
import {SignatureHelper} from "./lib/SignatureHelper.sol";

contract CallbacksTest is Test {
    CodeJar public codeJar;
    Counter public counter;
    QuarkStateManager public stateManager;

    uint256 alicePrivateKey = 0x9810473;
    address aliceAccount; // see constructor()
    QuarkWallet public aliceWallet;

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        stateManager = new QuarkStateManager();
        console.log("QuarkStateManager deployed to: %s", address(stateManager));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));

        aliceAccount = vm.addr(alicePrivateKey);
        aliceWallet = new QuarkWallet(aliceAccount, address(0), codeJar, stateManager);
    }

    function testCallbackFromCounter() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        assertEq(counter.number(), 0);

        bytes memory callbackFromCounter =
            new YulHelper().getDeployed("CallbackFromCounter.sol/CallbackFromCounter.json");

        uint96 nonce = aliceWallet.nextNonce();

        uint256[] memory requirements;
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptAddress: address(0),
            scriptSource: callbackFromCounter,
            scriptCalldata: abi.encodeWithSignature("doIncrementAndCallback(address)", counter),
            nonce: nonce,
            expiry: block.timestamp + 1000,
            allowCallback: true
        });
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op, v, r, s);
        assertEq(counter.number(), 11);
    }

    function testAllowNestedCallbacks() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory callbackFromCounter =
            new YulHelper().getDeployed("CallbackFromCounter.sol/CallbackFromCounter.json");
        bytes memory executeOtherScript =
            new YulHelper().getDeployed("ExecuteOtherOperation.sol/ExecuteOtherOperation.json");

        uint96 nonce1 = aliceWallet.nextNonce();
        uint256[] memory requirements;
        QuarkWallet.QuarkOperation memory nestedOp = QuarkWallet.QuarkOperation({
            scriptAddress: address(0),
            scriptSource: callbackFromCounter,
            scriptCalldata: abi.encodeWithSignature("doIncrementAndCallback(address)", counter),
            nonce: nonce1,
            expiry: block.timestamp + 1000,
            allowCallback: true
        });
        (uint8 v_, bytes32 r_, bytes32 s_) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, nestedOp);

        uint96 nonce2 = nonce1 + 1;
        QuarkWallet.QuarkOperation memory parentOp = QuarkWallet.QuarkOperation({
            scriptAddress: address(0),
            scriptSource: executeOtherScript,
            scriptCalldata: abi.encodeWithSelector(ExecuteOtherOperation.run.selector, nestedOp, v_, r_, s_),
            nonce: nonce2,
            expiry: block.timestamp + 1000,
            allowCallback: true
        });
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, parentOp);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(parentOp, v, r, s);
        assertEq(counter.number(), 11);
    }

    function testNestedCallWithNoCallbackSucceeds() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        assertEq(counter.number(), 0);

        bytes memory counterScript = new YulHelper().getDeployed("CounterScript.sol/CounterScript.json");
        bytes memory executeOtherScript =
            new YulHelper().getDeployed("ExecuteOtherOperation.sol/ExecuteOtherOperation.json");

        uint96 nonce1 = aliceWallet.nextNonce();
        uint256[] memory requirements;
        QuarkWallet.QuarkOperation memory nestedOp = QuarkWallet.QuarkOperation({
            scriptAddress: address(0),
            scriptSource: counterScript,
            scriptCalldata: abi.encodeWithSignature("run(address)", counter),
            nonce: nonce1,
            expiry: block.timestamp + 1000,
            allowCallback: false
        });
        (uint8 v_, bytes32 r_, bytes32 s_) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, nestedOp);

        uint96 nonce2 = nonce1 + 1;
        QuarkWallet.QuarkOperation memory parentOp = QuarkWallet.QuarkOperation({
            scriptAddress: address(0),
            scriptSource: executeOtherScript,
            scriptCalldata: abi.encodeWithSelector(ExecuteOtherOperation.run.selector, nestedOp, v_, r_, s_),
            nonce: nonce2,
            expiry: block.timestamp + 1000,
            allowCallback: true
        });
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, parentOp);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(parentOp, v, r, s);
        assertEq(counter.number(), 2);
    }

    function testAllowCallbackDoesNotRequireGettingCalledBack() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        assertEq(counter.number(), 0);
        bytes memory counterScript = new YulHelper().getDeployed("CounterScript.sol/CounterScript.json");
        uint96 nonce = aliceWallet.nextNonce();
        uint96[] memory requirements;
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptAddress: address(0),
            scriptSource: counterScript,
            scriptCalldata: abi.encodeWithSignature("run(address)", counter),
            nonce: nonce,
            expiry: block.timestamp + 1000,
            allowCallback: true
        });
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op, v, r, s);
        assertEq(counter.number(), 2);
    }

    function testRevertsOnCallbackWhenNoActiveCallback() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory callbackFromCounter =
            new YulHelper().getDeployed("CallbackFromCounter.sol/CallbackFromCounter.json");

        uint96 nonce = aliceWallet.nextNonce();
        uint256[] memory requirements;
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptAddress: address(0),
            scriptSource: callbackFromCounter,
            scriptCalldata: abi.encodeWithSignature("doIncrementAndCallback(address)", counter),
            nonce: nonce,
            expiry: block.timestamp + 1000,
            allowCallback: false
        });
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector, abi.encodeWithSelector(QuarkWallet.NoActiveCallback.selector)
            )
        );
        aliceWallet.executeQuarkOperation(op, v, r, s);
    }
}
