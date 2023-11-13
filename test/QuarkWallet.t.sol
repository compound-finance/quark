// SPDX-License-Identifier: BSD-3-Clause
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

    /* ===== immutable getters tests ===== */

    function testGetSigner() public {
        assertEq(aliceWallet.signer(), aliceAccount);
    }

    function testGetExecutor() public {
        assertEq(aliceWallet.executor(), address(0));
    }

    function testGetCodeJar() public {
        assertEq(address(aliceWallet.codeJar()), address(codeJar));
    }

    function testGetStateManager() public {
        assertEq(address(aliceWallet.stateManager()), address(stateManager));
    }

    /* ===== msg.value and msg.sender tests ===== */

    function testSetsMsgSenderAndValue() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        uint256 ethToSend = 3.2 ether;
        bytes memory getMessageDetails = new YulHelper().getDeployed("GetMessageDetails.sol/GetMessageDetails.json");
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            getMessageDetails,
            abi.encodeWithSignature("getMsgSenderAndValue()"),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWallet.executeQuarkOperation{value: ethToSend}(op, v, r, s);

        (address msgSender, uint256 msgValue) = abi.decode(result, (address, uint256));
        assertEq(msgSender, address(aliceWallet));
        assertEq(msgValue, ethToSend);
        assertEq(address(aliceWallet).balance, ethToSend);
    }

    function testSetsMsgSenderAndValueDuringDirectExecute() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        uint256 ethToSend = 3.2 ether;
        aliceAccount.call{value: ethToSend}("");
        QuarkWallet aliceWalletExecutable = new QuarkWallet(aliceAccount, aliceAccount, codeJar, stateManager);
        bytes memory getMessageDetails = new YulHelper().getDeployed("GetMessageDetails.sol/GetMessageDetails.json");
        uint96 nonce = aliceWalletExecutable.nextNonce();
        address scriptAddress = codeJar.saveCode(getMessageDetails);
        bytes memory call = abi.encodeWithSignature("getMsgSenderAndValue()");

        vm.startPrank(aliceAccount);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWalletExecutable.executeScript{value: ethToSend}(nonce, scriptAddress, call);

        vm.stopPrank();

        (address msgSender, uint256 msgValue) = abi.decode(result, (address, uint256));
        assertEq(msgSender, address(aliceWalletExecutable));
        assertEq(msgValue, ethToSend);
        assertEq(address(aliceWalletExecutable).balance, ethToSend);
    }

    /* ===== general invariant tests ===== */

    function testAllowAllNullNoopScript() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            nonce: aliceWallet.nextNonce(),
            scriptAddress: address(0),
            scriptSource: bytes(""),
            scriptCalldata: bytes(""),
            expiry: block.timestamp + 1000
        });
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();

        // operation containing no script or calldata is allowed
        aliceWallet.executeQuarkOperation(op, v, r, s);
        assertEq(stateManager.isNonceSet(address(aliceWallet), op.nonce), true);

        // direct execution of the null script with no calldata is allowed
        uint96 nonce = aliceWallet.nextNonce();
        vm.prank(aliceWallet.executor());
        aliceWallet.executeScript(nonce, address(0), bytes(""));
        assertEq(stateManager.isNonceSet(address(aliceWallet), nonce), true);
    }

    function testRevertsForOperationWithAddressAndSource() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            nonce: aliceWallet.nextNonce(),
            scriptAddress: address(0xc0c0),
            scriptSource: bytes("f00f00"),
            scriptCalldata: bytes("feefee"),
            expiry: block.timestamp + 1000
        });
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();

        vm.expectRevert(abi.encodeWithSelector(QuarkWallet.AmbiguousScript.selector));
        aliceWallet.executeQuarkOperation(op, v, r, s);
    }

    /* ===== replayability tests ===== */

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
        vm.expectRevert(abi.encodeWithSelector(QuarkStateManager.NonceAlreadySet.selector));
        aliceWallet.executeQuarkOperation(op1, v1, r1, s1);
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
        vm.expectRevert(abi.encodeWithSelector(QuarkStateManager.NonceAlreadySet.selector));
        aliceWallet.executeQuarkOperation(op, v, r, s);
    }

    /* ===== direct execution path tests ===== */

    function testRevertsForDirectExecuteByNonExecutorSigner() public {
        // gas: disable metering except while executing operations
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");
        assertEq(counter.number(), 0);

        // act as the signer for the wallet
        vm.startPrank(aliceWallet.signer());

        // pre-compute execution parameters so that the revert is expected from the right call
        uint96 nonce = aliceWallet.nextNonce();
        address target = codeJar.saveCode(incrementer);
        bytes memory call = abi.encodeWithSignature("incrementCounter(address)", counter);

        // gas: meter execute
        vm.resumeGasMetering();

        vm.expectRevert(abi.encodeWithSelector(QuarkWallet.Unauthorized.selector));
        aliceWallet.executeScript(nonce, target, call);

        vm.stopPrank();

        assertEq(counter.number(), 0);
    }

    function testRevertsForUnauthorizedDirectExecuteByRandomAddress() public {
        // gas: disable metering except while executing operations
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");
        assertEq(counter.number(), 0);

        // pre-compute execution parameters so that the revert is expected from the right call
        uint96 nonce = aliceWallet.nextNonce();
        address target = codeJar.saveCode(incrementer);
        bytes memory call = abi.encodeWithSignature("incrementCounter(address)", counter);

        // some arbitrary address cannot execute scripts directly on alice's wallet
        vm.startPrank(address(0xf00f00b47b47));

        // gas: meter execute
        vm.resumeGasMetering();

        vm.expectRevert(abi.encodeWithSelector(QuarkWallet.Unauthorized.selector));
        aliceWallet.executeScript(nonce, target, call);

        vm.stopPrank();

        assertEq(counter.number(), 0);
    }

    /* ===== basic operation tests, all run via both ScriptTypes ===== */

    function _testAtomicMaxCounter(ScriptType scriptType) internal {
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
        _testAtomicMaxCounter(ScriptType.ScriptSource);
    }

    function testAtomicMaxCounterScriptWithScriptAddress() public {
        _testAtomicMaxCounter(ScriptType.ScriptAddress);
    }

    function _testNoopScriptIsValid(ScriptType scriptType) internal {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet, abi.encode(), abi.encodeWithSignature("x()"), scriptType
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op, v, r, s);
        // expect the nonce to be spent by the no-op script
        assertEq(stateManager.isNonceSet(address(aliceWallet), op.nonce), true);
    }

    function testNoopScriptIsValidForScriptSource() public {
        _testNoopScriptIsValid(ScriptType.ScriptSource);
    }

    function testNoopScriptIsValidForScriptAddress() public {
        _testNoopScriptIsValid(ScriptType.ScriptAddress);
    }

    function _testQuarkOperationRevertsIfCallReverts(ScriptType scriptType) internal {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory revertsCode = new YulHelper().getDeployed("Reverts.sol/Reverts.json");
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOp(
            aliceWallet, revertsCode, scriptType
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert(
            abi.encodeWithSelector(QuarkWallet.QuarkCallError.selector, abi.encodeWithSelector(Reverts.Whoops.selector))
        );
        aliceWallet.executeQuarkOperation(op, v, r, s);
    }

    function testQuarkOperationWithScriptSourceRevertsIfCallReverts() public {
        _testQuarkOperationRevertsIfCallReverts(ScriptType.ScriptSource);
    }

    function testQuarkOperationWithScriptAddressRevertsIfCallReverts() public {
        _testQuarkOperationRevertsIfCallReverts(ScriptType.ScriptAddress);
    }

    function _testAtomicPing(ScriptType scriptType) internal {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory ping = new YulHelper().getDeployed("Logger.sol/Logger.json");
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOp(
            aliceWallet, ping, scriptType
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        // TODO: Check who emitted.
        vm.expectEmit(false, false, false, true);
        emit Ping(55);
        aliceWallet.executeQuarkOperation(op, v, r, s);
    }

    function testAtomicPingWithScriptSource() public {
        _testAtomicPing(ScriptType.ScriptSource);
    }

    function testAtomicPingWithScriptAddress() public {
        _testAtomicPing(ScriptType.ScriptAddress);
    }

    function _testAtomicIncrementer(ScriptType scriptType) internal {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");
        assertEq(counter.number(), 0);
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            incrementer,
            abi.encodeWithSignature("incrementCounter(address)", counter),
            scriptType
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op, v, r, s);
        assertEq(counter.number(), 3);
    }

    function testAtomicIncrementerWithScriptSource() public {
        _testAtomicIncrementer(ScriptType.ScriptSource);
    }

    function testAtomicIncrementerWithScriptAddress() public {
        _testAtomicIncrementer(ScriptType.ScriptAddress);
    }
}
