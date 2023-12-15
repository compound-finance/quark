// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "quark-core/src/CodeJar.sol";
import "quark-core/src/QuarkWallet.sol";
import "quark-core/src/QuarkStateManager.sol";

import "quark-core-scripts/src/Ethcall.sol";

import "test/lib/Logger.sol";
import "test/lib/Counter.sol";
import "test/lib/Reverts.sol";
import "test/lib/YulHelper.sol";
import "test/lib/Incrementer.sol";
import "test/lib/SignatureHelper.sol";
import "test/lib/PrecompileCaller.sol";
import "test/lib/MaxCounterScript.sol";
import "test/lib/GetMessageDetails.sol";
import "test/lib/CancelOtherScript.sol";
import "test/lib/QuarkOperationHelper.sol";

abstract contract AbstractQuarkWalletTest is Test {
    event Ping(uint256);
    event ClearNonce(address indexed wallet, uint96 nonce);

    CodeJar public codeJar; // see implementation constructor()
    Counter public counter; // see implementation constructor()
    QuarkStateManager public stateManager; // see implementation constructor()

    uint256 alicePrivateKey = 0x8675309;
    address aliceAccount = vm.addr(alicePrivateKey);
    QuarkWallet aliceWallet; // see implementation constructor()

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
        QuarkWallet aliceWalletExecutable = new QuarkWallet(aliceAccount, aliceAccount, codeJar, stateManager);
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
        vm.prank(aliceWallet.executor());
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
        QuarkWallet aliceWalletExecutable = new QuarkWallet(aliceAccount, aliceAccount, codeJar, stateManager);
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
        QuarkWallet aliceWalletExecutable = new QuarkWallet(aliceAccount, address(aliceWallet), codeJar, stateManager);
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
        vm.startPrank(aliceWallet.signer());

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
}
