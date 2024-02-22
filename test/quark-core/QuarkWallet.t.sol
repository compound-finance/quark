// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {YulHelper} from "test/lib/YulHelper.sol";
import {SignatureHelper} from "test/lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "test/lib/QuarkOperationHelper.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";
import {QuarkWallet, HasSignerExecutor, QuarkWalletMetadata} from "quark-core/src/QuarkWallet.sol";

import {QuarkMinimalProxy} from "quark-proxy/src/QuarkMinimalProxy.sol";

import {Ethcall} from "quark-core-scripts/src/Ethcall.sol";

import {Logger} from "test/lib/Logger.sol";
import {Counter} from "test/lib/Counter.sol";
import {Reverts} from "test/lib/Reverts.sol";
import {Incrementer} from "test/lib/Incrementer.sol";
import {PrecompileCaller} from "test/lib/PrecompileCaller.sol";
import {MaxCounterScript} from "test/lib/MaxCounterScript.sol";
import {GetMessageDetails} from "test/lib/GetMessageDetails.sol";
import {CancelOtherScript} from "test/lib/CancelOtherScript.sol";

contract QuarkWalletTest is Test {
    enum ExecutionType {
        Signature,
        Direct
    }

    event Ping(uint256);
    event ClearNonce(address indexed wallet, uint96 nonce);
    event ExecuteQuarkScript(
        address indexed executor, address indexed scriptAddress, uint96 indexed nonce, ExecutionType executionType
    );

    CodeJar public codeJar;
    Counter public counter;
    QuarkStateManager public stateManager;
    QuarkWallet public walletImplementation;

    uint256 alicePrivateKey = 0x8675309;
    address aliceAccount = vm.addr(alicePrivateKey);
    QuarkWallet aliceWallet; // see constructor()

    // wallet proxy instantiation helper
    function newWallet(address signer, address executor) internal returns (QuarkWallet) {
        return QuarkWallet(payable(new QuarkMinimalProxy(address(walletImplementation), signer, executor)));
    }

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));

        stateManager = new QuarkStateManager();
        console.log("QuarkStateManager deployed to: %s", address(stateManager));

        walletImplementation = new QuarkWallet(codeJar, stateManager);
        console.log("QuarkWallet implementation: %s", address(walletImplementation));

        aliceWallet = newWallet(aliceAccount, address(0));
        console.log("Alice signer: %s", aliceAccount);
        console.log("Alice wallet at: %s", address(aliceWallet));
    }

    /* ===== immutable getters tests ===== */

    function testGetSigner() public {
        assertEq(HasSignerExecutor(address(aliceWallet)).signer(), aliceAccount);
    }

    function testGetExecutor() public {
        assertEq(HasSignerExecutor(address(aliceWallet)).executor(), address(0));
    }

    function testGetCodeJar() public {
        assertEq(address(aliceWallet.codeJar()), address(codeJar));
    }

    function testGetStateManager() public {
        assertEq(address(aliceWallet.stateManager()), address(stateManager));
    }

    /* ===== msg.value and msg.sender tests ===== */

    function testSetsMsgSender() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory getMessageDetails = new YulHelper().getDeployed("GetMessageDetails.sol/GetMessageDetails.json");
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet, getMessageDetails, abi.encodeWithSignature("getMsgSenderAndValue()"), ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWallet.executeQuarkOperation(op, v, r, s);

        (address msgSender, uint256 msgValue) = abi.decode(result, (address, uint256));
        assertEq(msgSender, address(aliceWallet));
        assertEq(msgValue, 0);
    }

    function testSetsMsgSenderDuringDirectExecute() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        QuarkWallet aliceWalletExecutable = newWallet(aliceAccount, aliceAccount);
        bytes memory getMessageDetails = new YulHelper().getDeployed("GetMessageDetails.sol/GetMessageDetails.json");
        uint96 nonce = stateManager.nextNonce(address(aliceWalletExecutable));
        address scriptAddress = codeJar.saveCode(getMessageDetails);
        bytes memory call = abi.encodeWithSignature("getMsgSenderAndValue()");

        vm.startPrank(aliceAccount);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWalletExecutable.executeScript(nonce, scriptAddress, call);

        vm.stopPrank();

        (address msgSender, uint256 msgValue) = abi.decode(result, (address, uint256));
        assertEq(msgSender, address(aliceWalletExecutable));
        assertEq(msgValue, 0);
    }

    /* ===== event emission tests ===== */

    function testEmitsEventsInExecuteQuarkOperation() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory getMessageDetails = new YulHelper().getDeployed("GetMessageDetails.sol/GetMessageDetails.json");
        QuarkWallet.QuarkOperation memory opWithScriptAddress = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet, getMessageDetails, abi.encodeWithSignature("getMsgSenderAndValue()"), ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) =
            new SignatureHelper().signOp(alicePrivateKey, aliceWallet, opWithScriptAddress);
        QuarkWallet.QuarkOperation memory opWithScriptSource = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet, getMessageDetails, abi.encodeWithSignature("getMsgSenderAndValue()"), ScriptType.ScriptSource
        );
        opWithScriptSource.nonce += 1;
        (uint8 v2, bytes32 r2, bytes32 s2) =
            new SignatureHelper().signOp(alicePrivateKey, aliceWallet, opWithScriptSource);
        address scriptAddress = opWithScriptAddress.scriptAddress;

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectEmit(true, true, true, true);
        emit ExecuteQuarkScript(address(this), scriptAddress, opWithScriptAddress.nonce, ExecutionType.Signature);
        aliceWallet.executeQuarkOperation(opWithScriptAddress, v, r, s);

        vm.expectEmit(true, true, true, true);
        emit ExecuteQuarkScript(address(this), scriptAddress, opWithScriptSource.nonce, ExecutionType.Signature);
        aliceWallet.executeQuarkOperation(opWithScriptSource, v2, r2, s2);
    }

    function testEmitsEventsInDirectExecute() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        QuarkWallet aliceWalletExecutable = newWallet(aliceAccount, aliceAccount);
        bytes memory getMessageDetails = new YulHelper().getDeployed("GetMessageDetails.sol/GetMessageDetails.json");
        uint96 nonce = stateManager.nextNonce(address(aliceWalletExecutable));
        address scriptAddress = codeJar.saveCode(getMessageDetails);
        bytes memory call = abi.encodeWithSignature("getMsgSenderAndValue()");

        vm.startPrank(aliceAccount);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectEmit(true, true, true, true);
        emit ExecuteQuarkScript(address(aliceAccount), scriptAddress, nonce, ExecutionType.Direct);
        aliceWalletExecutable.executeScript(nonce, scriptAddress, call);
    }

    /* ===== general invariant tests ===== */

    function testDisallowAllNullNoopScript() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            nonce: stateManager.nextNonce(address(aliceWallet)),
            scriptAddress: address(0),
            scriptSource: bytes(""),
            scriptCalldata: bytes(""),
            expiry: block.timestamp + 1000
        });
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();

        // operation containing no script will revert
        vm.expectRevert(abi.encodeWithSelector(QuarkWallet.EmptyCode.selector));
        aliceWallet.executeQuarkOperation(op, v, r, s);

        // direct execution of the null script with no calldata will revert
        uint96 nonce = stateManager.nextNonce(address(aliceWallet));
        vm.prank(HasSignerExecutor(address(aliceWallet)).executor());
        vm.expectRevert(abi.encodeWithSelector(QuarkWallet.EmptyCode.selector));
        aliceWallet.executeScript(nonce, address(0), bytes(""));
    }

    function testRevertsForOperationWithAddressAndSource() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            nonce: stateManager.nextNonce(address(aliceWallet)),
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
        // gas: disable gas metering except while executing operations
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
        vm.expectEmit(true, true, true, true);
        emit ClearNonce(address(aliceWallet), op1.nonce);
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
        // gas: disable gas metering except while executing operations
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
            scriptAddress: address(counter),
            scriptSource: bytes(""),
            scriptCalldata: bytes(""),
            expiry: op1.expiry
        });
        (uint8 v2, bytes32 r2, bytes32 s2) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op2);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectEmit(true, true, true, true);
        emit ClearNonce(address(aliceWallet), op1.nonce);
        aliceWallet.executeQuarkOperation(op1, v1, r1, s1);
        // incrementer increments the counter thrice
        assertEq(counter.number(), 3);
        // when reusing the nonce but changing the script, revert
        vm.expectRevert(abi.encodeWithSelector(QuarkStateManager.NonceScriptMismatch.selector));
        aliceWallet.executeQuarkOperation(op2, v2, r2, s2);
    }

    function testRevertsForReplayOfCanceledScript() public {
        // gas: disable gas metering except while executing operations
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
        vm.expectEmit(true, true, true, true);
        emit ClearNonce(address(aliceWallet), op.nonce);
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

    function testDirectExecuteFromEOA() public {
        // gas: disable metering except while executing operations
        vm.pauseGasMetering();
        QuarkWallet aliceWalletExecutable = newWallet(aliceAccount, aliceAccount);
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");
        address incrementerAddress = codeJar.saveCode(incrementer);
        uint96 nonce = stateManager.nextNonce(address(aliceWalletExecutable));
        bytes memory call = abi.encodeWithSignature("incrementCounter(address)", counter);

        assertEq(counter.number(), 0);
        assertEq(stateManager.nextNonce(address(aliceWalletExecutable)), 0);

        // act as the executor for the wallet
        vm.startPrank(aliceAccount);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWalletExecutable.executeScript(nonce, incrementerAddress, call);

        assertEq(counter.number(), 3);
        assertEq(stateManager.nextNonce(address(aliceWalletExecutable)), 1);
    }

    function testDirectExecuteFromOtherQuarkWallet() public {
        // gas: disable metering except while executing operations
        vm.pauseGasMetering();
        QuarkWallet aliceWalletExecutable = newWallet(aliceAccount, address(aliceWallet));
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");
        bytes memory ethcall = new YulHelper().getDeployed("Ethcall.sol/Ethcall.json");
        address incrementerAddress = codeJar.saveCode(incrementer);
        bytes memory ethcallCalldata = abi.encodeWithSelector(
            Ethcall.run.selector,
            address(aliceWalletExecutable),
            abi.encodeWithSignature(
                "executeScript(uint96,address,bytes)",
                stateManager.nextNonce(address(aliceWalletExecutable)),
                incrementerAddress,
                abi.encodeWithSignature("incrementCounter(address)", counter)
            ),
            0 // value
        );

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet, ethcall, ethcallCalldata, ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        assertEq(counter.number(), 0);
        assertEq(stateManager.nextNonce(address(aliceWalletExecutable)), 0);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op, v, r, s);

        assertEq(counter.number(), 3);
        assertEq(stateManager.nextNonce(address(aliceWalletExecutable)), 1);
    }

    function testRevertsForDirectExecuteByNonExecutorSigner() public {
        // gas: disable metering except while executing operations
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");
        assertEq(counter.number(), 0);

        // act as the signer for the wallet
        vm.startPrank(HasSignerExecutor(address(aliceWallet)).signer());

        // pre-compute execution parameters so that the revert is expected from the right call
        uint96 nonce = stateManager.nextNonce(address(aliceWallet));
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
        uint96 nonce = stateManager.nextNonce(address(aliceWallet));
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

        // gas: do not meter walletStorage
        vm.pauseGasMetering();

        assertEq(counter.number(), 1);
        assertEq(uint256(stateManager.walletStorage(address(aliceWallet), op.nonce, keccak256("count"))), 1);

        // call twice
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op, v, r, s);

        // gas: do not meter walletStorage
        vm.pauseGasMetering();

        assertEq(counter.number(), 2);
        assertEq(uint256(stateManager.walletStorage(address(aliceWallet), op.nonce, keccak256("count"))), 2);

        // call thrice
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op, v, r, s);

        // gas: do not meter walletStorage
        vm.pauseGasMetering();

        assertEq(counter.number(), 3);
        assertEq(uint256(stateManager.walletStorage(address(aliceWallet), op.nonce, keccak256("count"))), 3);

        // revert because max has been hit
        vm.expectRevert(abi.encodeWithSelector(MaxCounterScript.EnoughAlready.selector));
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op, v, r, s);

        // gas: do not meter walletStorage
        vm.pauseGasMetering();

        assertEq(counter.number(), 3);
        assertEq(
            uint256(stateManager.walletStorage(address(aliceWallet), op.nonce, keccak256("count"))), counter.number()
        );

        counter.increment();
        assertEq(counter.number(), 4);
        assertEq(uint256(stateManager.walletStorage(address(aliceWallet), op.nonce, keccak256("count"))), 3);

        vm.resumeGasMetering();
        vm.stopPrank();
    }

    function testAtomicMaxCounterScriptWithScriptSource() public {
        _testAtomicMaxCounter(ScriptType.ScriptSource);
    }

    function testAtomicMaxCounterScriptWithScriptAddress() public {
        _testAtomicMaxCounter(ScriptType.ScriptAddress);
    }

    function _testEmptyScriptRevert(ScriptType scriptType) internal {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet, abi.encode(), abi.encodeWithSignature("x()"), scriptType
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert(abi.encodeWithSelector(QuarkWallet.EmptyCode.selector));
        aliceWallet.executeQuarkOperation(op, v, r, s);
    }

    function testEmptyScriptRevertForScriptSource() public {
        _testEmptyScriptRevert(ScriptType.ScriptSource);
    }

    function testEmptyScriptRevertForScriptAddress() public {
        _testEmptyScriptRevert(ScriptType.ScriptAddress);
    }

    function _testQuarkOperationRevertsIfCallReverts(ScriptType scriptType) internal {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory revertsCode = new YulHelper().getDeployed("Reverts.sol/Reverts.json");
        QuarkWallet.QuarkOperation memory op =
            new QuarkOperationHelper().newBasicOp(aliceWallet, revertsCode, scriptType);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert(abi.encodeWithSelector(Reverts.Whoops.selector));
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
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOp(aliceWallet, ping, scriptType);
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
            aliceWallet, incrementer, abi.encodeWithSignature("incrementCounter(address)", counter), scriptType
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

    /* ===== execution on Precompiles ===== */
    // Quark is no longer able call precompiles directly due to empty code check, so these tests are commented out

    function testPrecompileEcRecover() public {
        vm.pauseGasMetering();
        bytes memory preCompileCaller = new YulHelper().getDeployed("PrecompileCaller.sol/PrecompileCaller.json");
        bytes32 testHash = keccak256("test");
        (uint8 vt, bytes32 rt, bytes32 st) = vm.sign(alicePrivateKey, testHash);
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            preCompileCaller,
            abi.encodeCall(PrecompileCaller.ecrecoverCall, (testHash, vt, rt, st)),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
        vm.resumeGasMetering();
        bytes memory rawOut = aliceWallet.executeQuarkOperation(op, v, r, s);
        bytes memory output = abi.decode(rawOut, (bytes));
        assertEq(abi.decode(output, (address)), aliceAccount);
    }

    // function testPrecompileEcRecoverWithoutScript() public {
    //     vm.pauseGasMetering();
    //     bytes32 testHash = keccak256("test");
    //     (uint8 vt, bytes32 rt, bytes32 st) = vm.sign(alicePrivateKey, testHash);
    //     QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
    //         scriptAddress: address(0x1),
    //         scriptSource: "",
    //         scriptCalldata: abi.encode(testHash, vt, rt, st),
    //         nonce: aliceWallet.stateManager().nextNonce(address(aliceWallet)),
    //         expiry: block.timestamp + 1000
    //     });

    //     (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
    //     vm.resumeGasMetering();
    //     bytes memory rawOut = aliceWallet.executeQuarkOperation(op, v, r, s);
    //     assertEq(abi.decode(rawOut, (address)), aliceAccount);
    // }

    function testPrecompileSha256() public {
        vm.pauseGasMetering();
        bytes memory preCompileCaller = new YulHelper().getDeployed("PrecompileCaller.sol/PrecompileCaller.json");
        uint256 numberToHash = 123;
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            preCompileCaller,
            abi.encodeCall(PrecompileCaller.sha256Call, (numberToHash)),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
        vm.resumeGasMetering();
        bytes memory rawOut = aliceWallet.executeQuarkOperation(op, v, r, s);
        bytes memory output = abi.decode(rawOut, (bytes));
        assertEq(abi.decode(output, (bytes32)), sha256(abi.encodePacked(numberToHash)));
    }

    // function testPrecompileSha256WithoutScript() public {
    //     vm.pauseGasMetering();
    //     uint256 numberToHash = 123;
    //     QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
    //         scriptAddress: address(0x2),
    //         scriptSource: "",
    //         scriptCalldata: abi.encode(numberToHash),
    //         nonce: aliceWallet.stateManager().nextNonce(address(aliceWallet)),
    //         expiry: block.timestamp + 1000
    //     });

    //     (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
    //     vm.resumeGasMetering();
    //     bytes memory output = aliceWallet.executeQuarkOperation(op, v, r, s);
    //     assertEq(abi.decode(output, (bytes32)), sha256(abi.encodePacked(numberToHash)));
    // }

    function testPrecompileRipemd160() public {
        vm.pauseGasMetering();
        bytes memory preCompileCaller = new YulHelper().getDeployed("PrecompileCaller.sol/PrecompileCaller.json");
        bytes memory testBytes = abi.encodePacked(keccak256("test"));
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            preCompileCaller,
            abi.encodeCall(PrecompileCaller.ripemd160Call, (testBytes)),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
        vm.resumeGasMetering();
        bytes memory output = aliceWallet.executeQuarkOperation(op, v, r, s);
        assertEq(abi.decode(output, (bytes20)), ripemd160(testBytes));
    }

    // function testPrecompileRipemd160WithoutScript() public {
    //     vm.pauseGasMetering();
    //     bytes memory testBytes = abi.encodePacked(keccak256("test"));
    //     QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
    //         scriptAddress: address(0x3),
    //         scriptSource: "",
    //         scriptCalldata: testBytes,
    //         nonce: aliceWallet.stateManager().nextNonce(address(aliceWallet)),
    //         expiry: block.timestamp + 1000
    //     });
    //     (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
    //     vm.resumeGasMetering();
    //     bytes memory output = aliceWallet.executeQuarkOperation(op, v, r, s);
    //     assertEq(bytes20(abi.decode(output, (bytes32)) << 96), ripemd160(testBytes));
    // }

    function testPrecompileDataCopy() public {
        vm.pauseGasMetering();
        bytes memory preCompileCaller = new YulHelper().getDeployed("PrecompileCaller.sol/PrecompileCaller.json");
        bytes memory testBytes = abi.encodePacked(keccak256("testDataCopy"));
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            preCompileCaller,
            abi.encodeCall(PrecompileCaller.dataCopyCall, (testBytes)),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
        vm.resumeGasMetering();
        bytes memory output = aliceWallet.executeQuarkOperation(op, v, r, s);
        assertEq(abi.decode(output, (bytes)), testBytes);
    }

    // function testPrecompileDataCopyWithoutScript() public {
    //     vm.pauseGasMetering();
    //     bytes memory testBytes = abi.encodePacked(keccak256("testDataCopy"));
    //     QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
    //         scriptAddress: address(0x4),
    //         scriptSource: "",
    //         scriptCalldata: testBytes,
    //         nonce: aliceWallet.stateManager().nextNonce(address(aliceWallet)),
    //         expiry: block.timestamp + 1000
    //     });
    //     (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
    //     vm.resumeGasMetering();
    //     bytes memory output = aliceWallet.executeQuarkOperation(op, v, r, s);
    //     assertEq(output, testBytes);
    // }

    function testPrecompileBigModExp() public {
        vm.pauseGasMetering();
        bytes memory preCompileCaller = new YulHelper().getDeployed("PrecompileCaller.sol/PrecompileCaller.json");
        bytes32 base = bytes32(uint256(7));
        bytes32 exponent = bytes32(uint256(3));
        bytes32 modulus = bytes32(uint256(11));
        // 7^3 % 11 = 2
        bytes32 expected = bytes32(uint256(2));
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            preCompileCaller,
            abi.encodeCall(PrecompileCaller.bigModExpCall, (base, exponent, modulus)),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
        vm.resumeGasMetering();
        bytes memory output = aliceWallet.executeQuarkOperation(op, v, r, s);
        assertEq(abi.decode(output, (bytes32)), expected);
    }

    // function testPrecompileBigModExpWithoutScript() public {
    //     vm.pauseGasMetering();
    //     bytes32 base = bytes32(uint256(7));
    //     bytes32 exponent = bytes32(uint256(3));
    //     bytes32 modulus = bytes32(uint256(11));
    //     // 7^3 % 11 = 2
    //     bytes32 expected = bytes32(uint256(2));
    //     QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
    //         scriptAddress: address(0x5),
    //         scriptSource: "",
    //         scriptCalldata: abi.encode(uint256(0x20), uint256(0x20), uint256(0x20), base, exponent, modulus),
    //         nonce: aliceWallet.stateManager().nextNonce(address(aliceWallet)),
    //         expiry: block.timestamp + 1000
    //     });
    //     (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
    //     vm.resumeGasMetering();
    //     bytes memory output = aliceWallet.executeQuarkOperation(op, v, r, s);
    //     assertEq(abi.decode(output, (bytes32)), expected);
    // }

    function testPrecompileBn256Add() public {
        vm.pauseGasMetering();
        bytes memory preCompileCaller = new YulHelper().getDeployed("PrecompileCaller.sol/PrecompileCaller.json");
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            preCompileCaller,
            abi.encodeCall(PrecompileCaller.bn256AddCall, (uint256(1), uint256(2), uint256(1), uint256(2))),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
        vm.resumeGasMetering();
        bytes memory rawOut = aliceWallet.executeQuarkOperation(op, v, r, s);
        uint256[2] memory output = abi.decode(rawOut, (uint256[2]));
        assertEq(output[0], uint256(0x030644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd3));
        assertEq(output[1], uint256(0x15ed738c0e0a7c92e7845f96b2ae9c0a68a6a449e3538fc7ff3ebf7a5a18a2c4));
    }

    // function testPrecompileBn256AddWithoutScript() public {
    //     vm.pauseGasMetering();
    //     uint256[4] memory input;
    //     input[0] = uint256(1);
    //     input[1] = uint256(2);
    //     input[2] = uint256(1);
    //     input[3] = uint256(2);
    //     QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
    //         scriptAddress: address(0x6),
    //         scriptSource: "",
    //         scriptCalldata: abi.encode(input),
    //         nonce: aliceWallet.stateManager().nextNonce(address(aliceWallet)),
    //         expiry: block.timestamp + 1000
    //     });
    //     (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
    //     vm.resumeGasMetering();
    //     bytes memory rawOut = aliceWallet.executeQuarkOperation(op, v, r, s);
    //     uint256[2] memory output = abi.decode(rawOut, (uint256[2]));
    //     assertEq(output[0], uint256(0x030644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd3));
    //     assertEq(output[1], uint256(0x15ed738c0e0a7c92e7845f96b2ae9c0a68a6a449e3538fc7ff3ebf7a5a18a2c4));
    // }

    function testPrecompileBn256ScalarMul() public {
        vm.pauseGasMetering();
        bytes memory preCompileCaller = new YulHelper().getDeployed("PrecompileCaller.sol/PrecompileCaller.json");
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            preCompileCaller,
            abi.encodeCall(PrecompileCaller.bn256ScalarMulCall, (uint256(1), uint256(2), uint256(3))),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
        vm.resumeGasMetering();
        bytes memory rawOut = aliceWallet.executeQuarkOperation(op, v, r, s);
        uint256[2] memory output = abi.decode(rawOut, (uint256[2]));
        assertEq(output[0], uint256(0x0769bf9ac56bea3ff40232bcb1b6bd159315d84715b8e679f2d355961915abf0));
        assertEq(output[1], uint256(0x2ab799bee0489429554fdb7c8d086475319e63b40b9c5b57cdf1ff3dd9fe2261));
    }

    // function testPrecompileBn256ScalarMulWithoutScript() public {
    //     vm.pauseGasMetering();
    //     uint256[3] memory input;
    //     input[0] = uint256(1);
    //     input[1] = uint256(2);
    //     input[2] = uint256(3);
    //     QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
    //         scriptAddress: address(0x7),
    //         scriptSource: "",
    //         scriptCalldata: abi.encode(input),
    //         nonce: aliceWallet.stateManager().nextNonce(address(aliceWallet)),
    //         expiry: block.timestamp + 1000
    //     });
    //     (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
    //     vm.resumeGasMetering();
    //     bytes memory rawOut = aliceWallet.executeQuarkOperation(op, v, r, s);
    //     uint256[2] memory output = abi.decode(rawOut, (uint256[2]));
    //     assertEq(output[0], uint256(0x0769bf9ac56bea3ff40232bcb1b6bd159315d84715b8e679f2d355961915abf0));
    //     assertEq(output[1], uint256(0x2ab799bee0489429554fdb7c8d086475319e63b40b9c5b57cdf1ff3dd9fe2261));
    // }

    function testPrecompileBlake2F() public {
        vm.pauseGasMetering();
        bytes memory preCompileCaller = new YulHelper().getDeployed("PrecompileCaller.sol/PrecompileCaller.json");
        uint32 rounds = 12;

        bytes32[2] memory h;
        h[0] = hex"48c9bdf267e6096a3ba7ca8485ae67bb2bf894fe72f36e3cf1361d5f3af54fa5";
        h[1] = hex"d182e6ad7f520e511f6c3e2b8c68059b6bbd41fbabd9831f79217e1319cde05b";

        bytes32[4] memory m;
        m[0] = hex"6162630000000000000000000000000000000000000000000000000000000000";
        m[1] = hex"0000000000000000000000000000000000000000000000000000000000000000";
        m[2] = hex"0000000000000000000000000000000000000000000000000000000000000000";
        m[3] = hex"0000000000000000000000000000000000000000000000000000000000000000";

        bytes8[2] memory t;
        t[0] = hex"03000000";
        t[1] = hex"00000000";

        bool f = true;

        bytes32[2] memory expected;
        expected[0] = hex"ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d1";
        expected[1] = hex"7d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923";

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            preCompileCaller,
            abi.encodeCall(PrecompileCaller.blake2FCall, (rounds, h, m, t, f)),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
        vm.resumeGasMetering();
        bytes memory rawOut = aliceWallet.executeQuarkOperation(op, v, r, s);
        bytes32[2] memory output = abi.decode(rawOut, (bytes32[2]));
        assertEq(output[0], expected[0]);
        assertEq(output[1], expected[1]);
    }

    // function testPrecompileBlake2FWithoutScript() public {
    //     vm.pauseGasMetering();
    //     uint32 rounds = 12;

    //     bytes32[2] memory h;
    //     h[0] = hex"48c9bdf267e6096a3ba7ca8485ae67bb2bf894fe72f36e3cf1361d5f3af54fa5";
    //     h[1] = hex"d182e6ad7f520e511f6c3e2b8c68059b6bbd41fbabd9831f79217e1319cde05b";

    //     bytes32[4] memory m;
    //     m[0] = hex"6162630000000000000000000000000000000000000000000000000000000000";
    //     m[1] = hex"0000000000000000000000000000000000000000000000000000000000000000";
    //     m[2] = hex"0000000000000000000000000000000000000000000000000000000000000000";
    //     m[3] = hex"0000000000000000000000000000000000000000000000000000000000000000";

    //     bytes8[2] memory t;
    //     t[0] = hex"03000000";
    //     t[1] = hex"00000000";

    //     bool f = true;

    //     bytes32[2] memory expected;
    //     expected[0] = hex"ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d1";
    //     expected[1] = hex"7d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923";

    //     QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
    //         scriptAddress: address(0x9),
    //         scriptSource: "",
    //         scriptCalldata: abi.encodePacked(rounds, h[0], h[1], m[0], m[1], m[2], m[3], t[0], t[1], f),
    //         nonce: aliceWallet.stateManager().nextNonce(address(aliceWallet)),
    //         expiry: block.timestamp + 1000
    //     });
    //     (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
    //     vm.resumeGasMetering();
    //     bytes memory rawOut = aliceWallet.executeQuarkOperation(op, v, r, s);
    //     bytes32[2] memory output = abi.decode(rawOut, (bytes32[2]));
    //     assertEq(output[0], expected[0]);
    //     assertEq(output[1], expected[1]);
    // }

    function testRevertOnAllPrecompilesDirectCall() public {
        vm.pauseGasMetering();
        uint96 nonce = stateManager.nextNonce(address(aliceWallet));
        for (uint256 i = 1; i <= 9; i++) {
            vm.pauseGasMetering();
            QuarkWallet.QuarkOperation memory op = DummyQuarkOperation(address(uint160(i)), nonce++);
            (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
            vm.resumeGasMetering();
            vm.expectRevert(abi.encodeWithSelector(QuarkWallet.EmptyCode.selector));
            aliceWallet.executeQuarkOperation(op, v, r, s);
        }
    }

    function DummyQuarkOperation(address preCompileAddress, uint96 nonce)
        internal
        view
        returns (QuarkWallet.QuarkOperation memory)
    {
        return QuarkWallet.QuarkOperation({
            scriptAddress: preCompileAddress,
            scriptSource: "",
            scriptCalldata: hex"",
            nonce: nonce,
            expiry: block.timestamp + 1000
        });
    }
}
