pragma solidity 0.8.19;

import "forge-std/console.sol";

import {Test} from "forge-std/Test.sol";
import {QuarkWallet} from "../src/QuarkWallet.sol";
import {CodeJar} from "../src/CodeJar.sol";
import {Counter} from "./lib/Counter.sol";
import {YulHelper} from "./lib/YulHelper.sol";
import {QuarkStateManager} from "../src/QuarkStateManager.sol";
import {ExecuteOtherOperation} from "./lib/ExecuteOtherOperation.sol";
import {SignatureHelper} from "./lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "./lib/QuarkOperationHelper.sol";

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

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            callbackFromCounter,
            abi.encodeWithSignature("doIncrementAndCallback(address)", counter),
            ScriptType.ScriptSource
        );

        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op, v, r, s);
        assertEq(counter.number(), 11);
    }

    function testPayableCallback() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        uint256 ethToSend = 5.7 ether;
        assertEq(counter.number(), 0);
        assertEq(address(aliceWallet).balance, 0);

        bytes memory callbackFromCounter =
            new YulHelper().getDeployed("CallbackFromCounter.sol/CallbackFromCounter.json");

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            callbackFromCounter,
            abi.encodeWithSignature("doIncrementAndCallback(address)", counter),
            ScriptType.ScriptSource
        );

        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation{value: ethToSend}(op, v, r, s);

        assertEq(counter.number(), 11);
        assertEq(address(aliceWallet).balance, ethToSend);
    }

    function testAllowNestedCallbacks() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory callbackFromCounter =
            new YulHelper().getDeployed("CallbackFromCounter.sol/CallbackFromCounter.json");
        bytes memory executeOtherScript =
            new YulHelper().getDeployed("ExecuteOtherOperation.sol/ExecuteOtherOperation.json");

        QuarkWallet.QuarkOperation memory nestedOp = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            callbackFromCounter,
            abi.encodeWithSignature("doIncrementAndCallback(address)", counter),
            ScriptType.ScriptAddress
        );

        (uint8 v_, bytes32 r_, bytes32 s_) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, nestedOp);

        QuarkWallet.QuarkOperation memory parentOp = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            executeOtherScript,
            abi.encodeWithSelector(ExecuteOtherOperation.run.selector, nestedOp, v_, r_, s_),
            ScriptType.ScriptAddress
        );

        parentOp.nonce = nestedOp.nonce + 1;

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

        QuarkWallet.QuarkOperation memory nestedOp = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            counterScript,
            abi.encodeWithSignature("run(address)", counter),
            ScriptType.ScriptAddress
        );

        (uint8 v_, bytes32 r_, bytes32 s_) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, nestedOp);

        QuarkWallet.QuarkOperation memory parentOp = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            executeOtherScript,
            abi.encodeWithSelector(ExecuteOtherOperation.run.selector, nestedOp, v_, r_, s_),
            ScriptType.ScriptAddress
        );

        parentOp.nonce = nestedOp.nonce + 1;

        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, parentOp);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(parentOp, v, r, s);
        assertEq(counter.number(), 2);
    }

    function testRevertsOnCallbackWhenNoActiveCallback() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory ethcall = new YulHelper().getDeployed("Ethcall.sol/Ethcall.json");

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            ethcall,
            abi.encodeWithSignature(
                "run(address,bytes,uint256)",
                address(counter),
                abi.encodeCall(counter.incrementAndCallback, ()),
                0 /* value */
            ),
            ScriptType.ScriptSource
        );
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
