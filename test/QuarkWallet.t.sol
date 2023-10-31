// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/CodeJar.sol";
import "../src/QuarkWallet.sol";
import "../src/QuarkStateManager.sol";

import "./lib/Counter.sol";
import "./lib/MaxCounterScript.sol";
import "./lib/Reverts.sol";

import "./lib/YulHelper.sol";
import "./lib/SignatureHelper.sol";

contract QuarkWalletTest is Test {
    event Ping(uint256);

    enum ScriptType {
        ScriptAddress,
        ScriptSource
    }

    CodeJar public codeJar;
    Counter public counter;
    QuarkStateManager public stateManager;

    uint256 alicePrivateKey = 0x8675309;
    address aliceAccount = vm.addr(alicePrivateKey);
    QuarkWallet aliceWallet; // see constructor()

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));

        stateManager = new QuarkStateManager();
        console.log("QuarkStateManager deployed to: %s", address(stateManager));

        aliceWallet = new QuarkWallet(aliceAccount, codeJar, stateManager);
        console.log("Alice wallet at: %s", address(aliceWallet));
    }

    function newBasicOp(QuarkWallet wallet, bytes memory scriptSource, ScriptType scriptType)
        internal
        returns (QuarkWallet.QuarkOperation memory)
    {
        return newBasicOp(wallet, scriptSource, abi.encode(), scriptType);
    }

    // TODO: Make this a shared helper to be used by other test files
    function newBasicOp(
        QuarkWallet wallet,
        bytes memory scriptSource,
        bytes memory scriptCalldata,
        ScriptType scriptType
    ) internal returns (QuarkWallet.QuarkOperation memory) {
        address scriptAddress = codeJar.saveCode(scriptSource);
        if (scriptType == ScriptType.ScriptAddress) {
            return QuarkWallet.QuarkOperation({
                scriptAddress: scriptAddress,
                scriptSource: "",
                scriptCalldata: scriptCalldata,
                nonce: wallet.nextNonce(),
                expiry: block.timestamp + 1000,
                allowCallback: false
            });
        } else {
            return QuarkWallet.QuarkOperation({
                scriptAddress: address(0),
                scriptSource: scriptSource,
                scriptCalldata: scriptCalldata,
                nonce: wallet.nextNonce(),
                expiry: block.timestamp + 1000,
                allowCallback: false
            });
        }
    }

    function testGetOwner() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory getOwner = new YulHelper().getDeployed("GetOwner.sol/GetOwner.json");
        QuarkWallet.QuarkOperation memory op =
            newBasicOp(aliceWallet, getOwner, abi.encodeWithSignature("getOwner()"), ScriptType.ScriptSource);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWallet.executeQuarkOperation(op, v, r, s);
        assertEq(abi.decode(result, (address)), aliceAccount);
    }

    /* ===== Tests using script source ===== */

    function testQuarkOperationWithScriptSourceRevertsIfCodeNotFound() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        QuarkWallet.QuarkOperation memory op =
            newBasicOp(aliceWallet, abi.encode(), abi.encodeWithSignature("x()"), ScriptType.ScriptSource);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert(abi.encodeWithSelector(QuarkWallet.QuarkCodeNotFound.selector));
        aliceWallet.executeQuarkOperation(op, v, r, s);
    }

    function testQuarkOperationWithScriptSourceRevertsIfCallReverts() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory revertsCode = new YulHelper().getDeployed("Reverts.sol/Reverts.json");
        QuarkWallet.QuarkOperation memory op = newBasicOp(aliceWallet, revertsCode, ScriptType.ScriptSource);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert(
            abi.encodeWithSelector(QuarkWallet.QuarkCallError.selector, abi.encodeWithSelector(Reverts.Whoops.selector))
        );
        aliceWallet.executeQuarkOperation(op, v, r, s);
    }

    function testAtomicPingWithScriptSource() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory ping = new YulHelper().getDeployed("Logger.sol/Logger.json");
        QuarkWallet.QuarkOperation memory op = newBasicOp(aliceWallet, ping, ScriptType.ScriptSource);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        // TODO: Check who emitted.
        vm.expectEmit(false, false, false, true);
        emit Ping(55);
        aliceWallet.executeQuarkOperation(op, v, r, s);
    }

    function testAtomicIncrementerWithScriptSource() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");
        assertEq(counter.number(), 0);
        QuarkWallet.QuarkOperation memory op = newBasicOp(
            aliceWallet,
            incrementer,
            abi.encodeWithSignature("incrementCounter(address)", counter),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op, v, r, s);
        assertEq(counter.number(), 3);
    }

    function testAtomicMaxCounterScriptWithScriptSource() public {
        // gas: disable metering except while executing operations
        vm.pauseGasMetering();
        bytes memory maxCounterScript = new YulHelper().getDeployed("MaxCounterScript.sol/MaxCounterScript.json");
        assertEq(counter.number(), 0);

        vm.startPrank(address(aliceAccount));

        // call once
        {
            // gas: do not meter set-up
            vm.pauseGasMetering();
            QuarkWallet.QuarkOperation memory op = newBasicOp(
                aliceWallet, maxCounterScript, abi.encodeCall(MaxCounterScript.run, (counter)), ScriptType.ScriptSource
            );
            (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
            // gas: meter execute
            vm.resumeGasMetering();
            aliceWallet.executeQuarkOperation(op, v, r, s);
        }
        assertEq(counter.number(), 1);

        // call twice
        {
            // gas: do not meter set-up
            vm.pauseGasMetering();
            QuarkWallet.QuarkOperation memory op = newBasicOp(
                aliceWallet, maxCounterScript, abi.encodeCall(MaxCounterScript.run, (counter)), ScriptType.ScriptSource
            );
            (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
            // gas: meter execute
            vm.resumeGasMetering();
            aliceWallet.executeQuarkOperation(op, v, r, s);
        }
        assertEq(counter.number(), 2);

        // call thrice
        {
            // gas: do not meter set-up
            vm.pauseGasMetering();
            QuarkWallet.QuarkOperation memory op = newBasicOp(
                aliceWallet, maxCounterScript, abi.encodeCall(MaxCounterScript.run, (counter)), ScriptType.ScriptSource
            );
            (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
            // gas: meter execute
            vm.resumeGasMetering();
            aliceWallet.executeQuarkOperation(op, v, r, s);
        }
        assertEq(counter.number(), 3);

        // revert because max has been hit
        {
            // gas: do not meter set-up
            vm.pauseGasMetering();
            QuarkWallet.QuarkOperation memory op = newBasicOp(
                aliceWallet, maxCounterScript, abi.encodeCall(MaxCounterScript.run, (counter)), ScriptType.ScriptSource
            );
            (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
            // gas: meter execute
            vm.resumeGasMetering();
            vm.expectRevert(
                abi.encodeWithSelector(
                    QuarkWallet.QuarkCallError.selector, abi.encodeWithSelector(MaxCounterScript.EnoughAlready.selector)
                )
            );
            aliceWallet.executeQuarkOperation(op, v, r, s);
        }
        assertEq(counter.number(), 3);

        vm.stopPrank();
    }

    /* ===== Tests using script address ===== */

    function testQuarkOperationWithScriptAddressRevertsIfCodeNotFound() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        QuarkWallet.QuarkOperation memory op =
            newBasicOp(aliceWallet, abi.encode(), abi.encodeWithSignature("x()"), ScriptType.ScriptAddress);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert(abi.encodeWithSelector(QuarkWallet.QuarkCodeNotFound.selector));
        aliceWallet.executeQuarkOperation(op, v, r, s);
    }

    function testQuarkOperationWithScriptAddressRevertsIfCallReverts() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory revertsCode = new YulHelper().getDeployed("Reverts.sol/Reverts.json");
        QuarkWallet.QuarkOperation memory op = newBasicOp(aliceWallet, revertsCode, ScriptType.ScriptAddress);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert(
            abi.encodeWithSelector(QuarkWallet.QuarkCallError.selector, abi.encodeWithSelector(Reverts.Whoops.selector))
        );
        aliceWallet.executeQuarkOperation(op, v, r, s);
    }

    function testAtomicPingWithScriptAddress() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory ping = new YulHelper().getDeployed("Logger.sol/Logger.json");
        QuarkWallet.QuarkOperation memory op = newBasicOp(aliceWallet, ping, ScriptType.ScriptAddress);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        // TODO: Check who emitted.
        vm.expectEmit(false, false, false, true);
        emit Ping(55);
        aliceWallet.executeQuarkOperation(op, v, r, s);
    }

    function testAtomicIncrementerWithScriptAddress() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");
        assertEq(counter.number(), 0);
        QuarkWallet.QuarkOperation memory op = newBasicOp(
            aliceWallet,
            incrementer,
            abi.encodeWithSignature("incrementCounter(address)", counter),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op, v, r, s);
        assertEq(counter.number(), 3);
    }

    function testAtomicMaxCounterScriptWithScriptAddress() public {
        // gas: disable metering except while executing operations
        vm.pauseGasMetering();
        bytes memory maxCounterScript = new YulHelper().getDeployed("MaxCounterScript.sol/MaxCounterScript.json");
        assertEq(counter.number(), 0);

        vm.startPrank(address(aliceAccount));

        // call once
        {
            // gas: do not meter set-up
            vm.pauseGasMetering();
            QuarkWallet.QuarkOperation memory op = newBasicOp(
                aliceWallet, maxCounterScript, abi.encodeCall(MaxCounterScript.run, (counter)), ScriptType.ScriptAddress
            );
            (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
            // gas: meter execute
            vm.resumeGasMetering();
            aliceWallet.executeQuarkOperation(op, v, r, s);
        }
        assertEq(counter.number(), 1);

        // call twice
        {
            // gas: do not meter set-up
            vm.pauseGasMetering();
            QuarkWallet.QuarkOperation memory op = newBasicOp(
                aliceWallet, maxCounterScript, abi.encodeCall(MaxCounterScript.run, (counter)), ScriptType.ScriptAddress
            );
            (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
            // gas: meter execute
            vm.resumeGasMetering();
            aliceWallet.executeQuarkOperation(op, v, r, s);
        }
        assertEq(counter.number(), 2);

        // call thrice
        {
            // gas: do not meter set-up
            vm.pauseGasMetering();
            QuarkWallet.QuarkOperation memory op = newBasicOp(
                aliceWallet, maxCounterScript, abi.encodeCall(MaxCounterScript.run, (counter)), ScriptType.ScriptAddress
            );
            (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
            // gas: meter execute
            vm.resumeGasMetering();
            aliceWallet.executeQuarkOperation(op, v, r, s);
        }
        assertEq(counter.number(), 3);

        // revert because max has been hit
        {
            // gas: do not meter set-up
            vm.pauseGasMetering();
            QuarkWallet.QuarkOperation memory op = newBasicOp(
                aliceWallet, maxCounterScript, abi.encodeCall(MaxCounterScript.run, (counter)), ScriptType.ScriptAddress
            );
            (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
            // gas: meter execute
            vm.resumeGasMetering();
            vm.expectRevert(
                abi.encodeWithSelector(
                    QuarkWallet.QuarkCallError.selector, abi.encodeWithSelector(MaxCounterScript.EnoughAlready.selector)
                )
            );
            aliceWallet.executeQuarkOperation(op, v, r, s);
        }
        assertEq(counter.number(), 3);

        vm.stopPrank();
    }

    function testRevertsForReusedNonceWithChangedScript() public {
        // gas: disable gas metering except while executing operatoins
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");
        bytes memory getOwner = new YulHelper().getDeployed("GetOwner.sol/GetOwner.json");

        // 1. use nonce to increment a counter
        QuarkWallet.QuarkOperation memory op1 = newBasicOp(
            aliceWallet, incrementer, abi.encodeWithSignature("incrementCounterReplayable(address)", address(counter))
        );
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op1);

        QuarkWallet.QuarkOperation memory op2 = QuarkWallet.QuarkOperation({
            nonce: op1.nonce,
            scriptSource: getOwner,
            scriptCalldata: abi.encodeWithSignature("getOwner()"),
            expiry: block.timestamp + 1000,
            allowCallback: false
        });
        (uint8 v2, bytes32 r2, bytes32 s2) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op2);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op1, v1, r1, s1);
        // incrementer increments the counter thrice
        assertEq(counter.number(), 3);
        // when reusing the nonce but changing the script, revert
        vm.expectRevert(abi.encodeWithSelector(QuarkStateManager.NonceCallbackMismatch.selector));
        aliceWallet.executeQuarkOperation(op2, v2, r2, s2);
    }

    function testRevertsForReusedNonceWithChangedCalldata() public {
        // gas: disable gas metering except while executing operatoins
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");

        // 1. use nonce to increment a counter
        QuarkWallet.QuarkOperation memory op1 = newBasicOp(
            aliceWallet, incrementer, abi.encodeWithSignature("incrementCounterReplayable(address)", address(counter))
        );
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op1);

        QuarkWallet.QuarkOperation memory op2 = QuarkWallet.QuarkOperation({
            nonce: op1.nonce,
            scriptSource: incrementer,
            scriptCalldata: abi.encodeWithSignature("incrementCounter(address)", address(counter)),
            expiry: block.timestamp + 1000,
            allowCallback: false
        });
        (uint8 v2, bytes32 r2, bytes32 s2) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op2);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op1, v1, r1, s1);
        // incrementer increments the counter thrice
        assertEq(counter.number(), 3);
        // when reusing the nonce but changing the calldata, revert
        vm.expectRevert(abi.encodeWithSelector(QuarkStateManager.NonceCallbackMismatch.selector));
        aliceWallet.executeQuarkOperation(op2, v2, r2, s2);
    }

    function testRevertsForReusedNonceWithChangedFlags() public {
        // gas: disable gas metering except while executing operatoins
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");

        // 1. use nonce to increment a counter
        QuarkWallet.QuarkOperation memory op1 = newBasicOp(
            aliceWallet, incrementer, abi.encodeWithSignature("incrementCounterReplayable(address)", address(counter))
        );
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op1);

        QuarkWallet.QuarkOperation memory op2 = QuarkWallet.QuarkOperation({
            nonce: op1.nonce,
            scriptSource: op1.scriptSource,
            scriptCalldata: op1.scriptCalldata,
            expiry: op1.expiry,
            allowCallback: !op1.allowCallback // invert the allowCallback flag
        });
        (uint8 v2, bytes32 r2, bytes32 s2) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op2);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op1, v1, r1, s1);
        // incrementer increments the counter thrice
        assertEq(counter.number(), 3);
        // when reusing the nonce but changing the calldata, revert
        vm.expectRevert(abi.encodeWithSelector(QuarkStateManager.NonceCallbackMismatch.selector));
        aliceWallet.executeQuarkOperation(op2, v2, r2, s2);
    }

    function testEmptyScriptCancelsReplayableNonce() public {
        // gas: disable gas metering except while executing operatoins
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");

        QuarkWallet.QuarkOperation memory op = newBasicOp(
            aliceWallet, incrementer, abi.encodeWithSignature("incrementCounterReplayable(address)", address(counter))
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        QuarkWallet.QuarkOperation memory cancelOp = QuarkWallet.QuarkOperation({
            nonce: op.nonce,
            scriptSource: hex"",
            scriptCalldata: hex"",
            expiry: block.timestamp + 1000,
            allowCallback: false
        });
        (uint8 cancel_v, bytes32 cancel_r, bytes32 cancel_s) =
            new SignatureHelper().signOp(alicePrivateKey, aliceWallet, cancelOp);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op, v, r, s);
        assertEq(counter.number(), 3);
        // can replay the same operation...
        aliceWallet.executeQuarkOperation(op, v, r, s);
        assertEq(counter.number(), 6);
        // can cancel the replayable nonce...
        aliceWallet.executeQuarkOperation(cancelOp, cancel_v, cancel_r, cancel_s);
        // and now you can no longer replay
        vm.expectRevert(abi.encodeWithSelector(QuarkWallet.InvalidNonce.selector));
        // XXX: shouldn't we let the state manager do the nonce checking?
        // vm.expectRevert(abi.encodeWithSelector(QuarkStateManager.NonceAlreadySet.selector));
        aliceWallet.executeQuarkOperation(op, v, r, s);
    }
}
