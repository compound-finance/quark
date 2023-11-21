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
            aliceWallet, counterScript, abi.encodeWithSignature("run(address)", counter), ScriptType.ScriptAddress
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
        vm.expectRevert(abi.encodeWithSelector(QuarkWallet.NoActiveCallback.selector));
        aliceWallet.executeQuarkOperation(op, v, r, s);
    }

    function testCallcodeReentrancyExploit() public {
        /*
         * Notably, Quark uses `callcode` instead of `delegatecall` to execute
         * script bytecode in the context of a wallet. Why is that?
         *
         * Well, callcode changes `msg.sender` to the caller, which is in our case the wallet itself,
         * while otherwise working (for our purposes) like `delegatecall`. Why do we want that?
         *   (a) msg.sender can otherwise be pretty much any address, making it difficult to use
         *   (b) if we use `callcode`, we can see when `msg.sender == address(this)` to check if
         *       the script was called directly from the wallet for re-entrancy guards.
         *
         * (a) msg.sender is probably an arbitrary address; usually, the submitter of a signed QuarkOperation.
         * One use-case for knowing the submitter would be to pay them; however, this can still be done
         * (and more reliably) using tx.origin. So there is very little use for the default msg.sender.
         *
         * (b) Quark wallets are able to accept callbacks within a transaction, which is what enables
         * scripts to do things like execute a Uniswap FlashLoan. However, what if a script calls out to
         * a third-party contract, like Uniswap but malicious, and receives a callback other than the one
         * expected? What if the third-party calls back into the entrypoint of the script and recursively
         * drains the wallet's funds? Using `callcode` gives us a mechanism for detecting just that: when
         * the wallet `callcode`s into the script at the beginning of the transaction,
         * `msg.sender == address(this)`. If and when a callback is performed, the wallet will use
         * `delegatecall`, and `msg.sender` will not be the wallet address. So we can protect
         * methods from outside callers by guarding on the condition `msg.sender == address(this)`,
         * preventing malicious callback executors from triggering recursive callbacks and exploiting the wallet.
         */
        vm.pauseGasMetering();
        bytes memory exploitableScript = new YulHelper().getDeployed("CallcodeReentrancy.sol/ExploitableScript.json");
        bytes memory callbackCaller = new YulHelper().getDeployed("CallcodeReentrancy.sol/CallbackCaller.json");

        address callbackCallerAddress = codeJar.saveCode(callbackCaller);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            exploitableScript,
            abi.encodeWithSignature(
                "callMeBack(address,bytes,uint256)",
                callbackCallerAddress,
                abi.encodeWithSignature("doubleDip(bool)", false),
                500 wei /* fee */
            ),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        deal(address(aliceWallet), 1000 wei);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation{value: 1000 wei}(op, v, r, s);
        assertEq(callbackCallerAddress.balance, 1000 wei);
    }

    function testCallcodeReentrancyProtection() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory protectedScript = new YulHelper().getDeployed("CallcodeReentrancy.sol/ProtectedScript.json");
        bytes memory callbackCaller = new YulHelper().getDeployed("CallcodeReentrancy.sol/CallbackCaller.json");

        address callbackCallerAddress = codeJar.saveCode(callbackCaller);

        QuarkWallet.QuarkOperation memory badOp = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            protectedScript,
            abi.encodeWithSignature(
                "callMeBack(address,bytes,uint256)",
                callbackCallerAddress,
                abi.encodeWithSignature("doubleDip(bool)", false),
                500 wei /* fee */
            ),
            ScriptType.ScriptAddress
        );
        (uint8 bad_v, bytes32 bad_r, bytes32 bad_s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, badOp);

        deal(address(aliceWallet), 1000 wei);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert(); // attacker tried to call back into the script with a changed fee
        aliceWallet.executeQuarkOperation{value: 1000 wei}(badOp, bad_v, bad_r, bad_s);

        // gas: do not meter set-up
        vm.pauseGasMetering();

        QuarkWallet.QuarkOperation memory behavedOp = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            protectedScript,
            abi.encodeWithSignature(
                "callMeBack(address,bytes,uint256)",
                callbackCallerAddress,
                abi.encodeWithSignature("beGood()"),
                500 wei /* fee */
            ),
            ScriptType.ScriptAddress
        );
        (uint8 behaved_v, bytes32 behaved_r, bytes32 behaved_s) =
            new SignatureHelper().signOp(alicePrivateKey, aliceWallet, behavedOp);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation{value: 1000 wei}(behavedOp, behaved_v, behaved_r, behaved_s);
        // the well-behaved callback caller gets the correct fee
        assertEq(callbackCallerAddress.balance, 500 wei);
    }
}
