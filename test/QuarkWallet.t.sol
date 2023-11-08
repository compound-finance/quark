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
import "./lib/QuarkOperationHelper.sol";
import "./lib/QuarkStateManagerHarness.sol";

contract QuarkWalletTest is Test {
    event Ping(uint256);

    CodeJar public codeJar;
    Counter public counter;
    QuarkStateManagerHarness public stateManager;

    uint256 alicePrivateKey = 0x8675309;
    address aliceAccount = vm.addr(alicePrivateKey);
    QuarkWallet aliceWallet; // see constructor()

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));

        stateManager = new QuarkStateManagerHarness();
        console.log("QuarkStateManagerHarness deployed to: %s", address(stateManager));

        aliceWallet = new QuarkWallet(aliceAccount, address(0), codeJar, stateManager);
        console.log("Alice signer: %s", aliceAccount);
        console.log("Alice wallet at: %s", address(aliceWallet));
    }

    function testGetRoleSigner() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory getRole = new YulHelper().getDeployed("GetRole.sol/GetRole.json");
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            getRole,
            abi.encodeWithSignature("getSigner()"),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWallet.executeQuarkOperation(op, v, r, s);
        assertEq(abi.decode(result, (address)), aliceWallet.signer());
        assertEq(aliceWallet.signer(), aliceAccount);
    }

    function testGetRoleExecutor() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory getRole = new YulHelper().getDeployed("GetRole.sol/GetRole.json");
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            getRole,
            abi.encodeWithSignature("getExecutor()"),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWallet.executeQuarkOperation(op, v, r, s);
        assertEq(abi.decode(result, (address)), aliceWallet.executor());
        assertEq(aliceWallet.executor(), address(0));
    }

    /* ===== Tests using script source ===== */

    function testQuarkOperationWithScriptSourceRevertsIfCodeNotFound() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            abi.encode(),
            abi.encodeWithSignature("x()"),
            ScriptType.ScriptSource
        );
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
        QuarkWallet.QuarkOperation memory op =
            new QuarkOperationHelper().newBasicOp(aliceWallet, revertsCode, ScriptType.ScriptSource);
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
        QuarkWallet.QuarkOperation memory op =
            new QuarkOperationHelper().newBasicOp(aliceWallet, ping, ScriptType.ScriptSource);
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
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
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

    function _testAtomicMaxCounterWithScriptType(ScriptType scriptType) internal {
        // gas: disable metering except while executing operations
        vm.pauseGasMetering();

        bytes memory maxCounterScript = new YulHelper().getDeployed("MaxCounterScript.sol/MaxCounterScript.json");
        assertEq(counter.number(), 0);

        vm.startPrank(address(aliceAccount));

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet, maxCounterScript, abi.encodeCall(MaxCounterScript.run, (counter)), scriptType
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // call once
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op, v, r, s);

        // gas: do not meter readRawUnsafe
        vm.pauseGasMetering();

        assertEq(counter.number(), 1);
        assertEq(uint256(stateManager.readRawUnsafe(aliceWallet, op.nonce, "count")), 1);

        // call twice
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op, v, r, s);

        // gas: do not meter readRawUnsafe
        vm.pauseGasMetering();

        assertEq(counter.number(), 2);
        assertEq(uint256(stateManager.readRawUnsafe(aliceWallet, op.nonce, "count")), 2);

        // call thrice
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op, v, r, s);

        // gas: do not meter readRawUnsafe
        vm.pauseGasMetering();

        assertEq(counter.number(), 3);
        assertEq(uint256(stateManager.readRawUnsafe(aliceWallet, op.nonce, "count")), 3);

        // revert because max has been hit
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector, abi.encodeWithSelector(MaxCounterScript.EnoughAlready.selector)
            )
        );
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op, v, r, s);

        // gas: do not meter readRawUnsafe()
        vm.pauseGasMetering();

        assertEq(counter.number(), 3);
        assertEq(uint256(stateManager.readRawUnsafe(aliceWallet, op.nonce, "count")), counter.number());

        counter.increment();
        assertEq(counter.number(), 4);
        assertEq(uint256(stateManager.readRawUnsafe(aliceWallet, op.nonce, "count")), 3);

        vm.resumeGasMetering();
        vm.stopPrank();
    }

    function testAtomicMaxCounterScriptWithScriptSource() public {
        _testAtomicMaxCounterWithScriptType(ScriptType.ScriptSource);
    }

    /* ===== Tests using script address ===== */

    function testQuarkOperationWithScriptAddressRevertsIfCodeNotFound() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet, abi.encode(), abi.encodeWithSignature("x()"), ScriptType.ScriptAddress
        );
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
        QuarkWallet.QuarkOperation memory op =
            new QuarkOperationHelper().newBasicOp(aliceWallet, revertsCode, ScriptType.ScriptAddress);
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
        QuarkWallet.QuarkOperation memory op =
            new QuarkOperationHelper().newBasicOp(aliceWallet, ping, ScriptType.ScriptAddress);
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
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
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
        _testAtomicMaxCounterWithScriptType(ScriptType.ScriptAddress);
    }

    function testRevertsForReusedNonceWithChangedScript() public {
        // gas: disable gas metering except while executing operatoins
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");
        bytes memory getRole = new YulHelper().getDeployed("GetRole.sol/GetRole.json");

        // 1. use nonce to increment a counter
        QuarkWallet.QuarkOperation memory op1 = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            incrementer,
            abi.encodeWithSignature("incrementCounterReplayable(address)", address(counter)),
            ScriptType.ScriptAddress
        );
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op1);

        QuarkWallet.QuarkOperation memory op2 = QuarkWallet.QuarkOperation({
            nonce: op1.nonce,
            scriptAddress: address(0),
            scriptSource: getRole,
            scriptCalldata: abi.encodeWithSignature("getOwner()"),
            expiry: block.timestamp + 1000
        });
        (uint8 v2, bytes32 r2, bytes32 s2) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op2);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op1, v1, r1, s1);
        // incrementer increments the counter thrice
        assertEq(counter.number(), 3);
        // when reusing the nonce but changing the script, revert
        vm.expectRevert(abi.encodeWithSelector(QuarkStateManager.NonceScriptMismatch.selector));
        aliceWallet.executeQuarkOperation(op2, v2, r2, s2);
    }

    function testCanReplaySameScriptWithDifferentCall() public {
        // gas: disable gas metering except while executing operatoins
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");

        // 1. use nonce to increment a counter
        QuarkWallet.QuarkOperation memory op1 = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            incrementer,
            abi.encodeWithSignature("incrementCounterReplayable(address)", address(counter)),
            ScriptType.ScriptAddress
        );
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op1);

        QuarkWallet.QuarkOperation memory op2 = QuarkWallet.QuarkOperation({
            nonce: op1.nonce,
            scriptAddress: address(0),
            scriptSource: incrementer,
            scriptCalldata: abi.encodeWithSignature("incrementCounter(address)", address(counter)),
            expiry: block.timestamp + 1000
        });
        (uint8 v2, bytes32 r2, bytes32 s2) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op2);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op1, v1, r1, s1);
        // incrementer increments the counter thrice
        assertEq(counter.number(), 3);
        // when reusing the nonce, you can change the call
        aliceWallet.executeQuarkOperation(op2, v2, r2, s2);
        // incrementer increments the counter thrice
        assertEq(counter.number(), 6);
        // but now that we did not use a replayable call, it is canceled
        vm.expectRevert(abi.encodeWithSelector(QuarkWallet.InvalidNonce.selector));
        aliceWallet.executeQuarkOperation(op1, v1, r1, s1);
    }

    function testRevertsForReplayOfCanceledScript() public {
        // gas: disable gas metering except while executing operatoins
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");
        bytes memory cancelOtherScript = new YulHelper().getDeployed("CancelOtherScript.sol/CancelOtherScript.json");

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            incrementer,
            abi.encodeWithSignature("incrementCounterReplayable(address)", address(counter)),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op, v, r, s);
        assertEq(counter.number(), 3);
        // can replay the same operation...
        aliceWallet.executeQuarkOperation(op, v, r, s);
        assertEq(counter.number(), 6);

        // can cancel the replayable nonce...
        vm.pauseGasMetering();
        QuarkWallet.QuarkOperation memory cancelOtherOp = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet, cancelOtherScript, abi.encodeWithSignature("run(uint96)", op.nonce), ScriptType.ScriptAddress
        );
        (uint8 cancel_v, bytes32 cancel_r, bytes32 cancel_s) =
            new SignatureHelper().signOp(alicePrivateKey, aliceWallet, cancelOtherOp);
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(cancelOtherOp, cancel_v, cancel_r, cancel_s);

        // and now you can no longer replay
        vm.expectRevert(abi.encodeWithSelector(QuarkWallet.InvalidNonce.selector));
        // XXX: shouldn't we let the state manager do the nonce checking?
        // vm.expectRevert(abi.encodeWithSelector(QuarkStateManager.NonceAlreadySet.selector));
        aliceWallet.executeQuarkOperation(op, v, r, s);
    }

    function testSignerCanDirectExecute() public {
        // gas: disable metering except while executing operations
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");
        assertEq(counter.number(), 0);

        vm.startPrank(aliceAccount);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeScript(
            aliceWallet.nextNonce(),
            codeJar.saveCode(incrementer),
            abi.encodeWithSignature("incrementCounter(address)", counter)
        );

        vm.stopPrank();

        assertEq(counter.number(), 3);
    }

    function testDirectExecuteUnauthorized() public {
        // gas: disable metering except while executing operations
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");
        assertEq(counter.number(), 0);

        // gas: meter execute
        vm.resumeGasMetering();
        uint96 nonce = aliceWallet.nextNonce();
        address target = codeJar.saveCode(incrementer);
        bytes memory call = abi.encodeWithSignature("incrementCounter(address)", counter);
        vm.expectRevert(abi.encodeWithSelector(QuarkWallet.Unauthorized.selector));
        aliceWallet.executeScript(nonce, target, call);

        assertEq(counter.number(), 0);
    }
}
