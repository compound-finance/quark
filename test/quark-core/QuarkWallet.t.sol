// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

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

import {Ethcall} from "quark-core-scripts/src/Ethcall.sol";

import {Logger} from "test/lib/Logger.sol";
import {Counter} from "test/lib/Counter.sol";
import {Reverts} from "test/lib/Reverts.sol";
import {EmptyCode} from "test/lib/EmptyCode.sol";
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
    event ExecuteQuarkScript(
        address indexed executor,
        address indexed scriptAddress,
        bytes32 indexed nonce,
        bytes32 submissionToken,
        ExecutionType executionType
    );

    CodeJar public codeJar;
    Counter public counter;
    QuarkNonceManager public nonceManager;
    QuarkWallet public walletImplementation;

    uint256 alicePrivateKey = 0x8675309;
    address aliceAccount = vm.addr(alicePrivateKey);
    QuarkWallet aliceWallet; // see constructor()

    bytes32 constant EXHAUSTED_TOKEN = bytes32(type(uint256).max);

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

        nonceManager = new QuarkNonceManager();
        console.log("QuarkNonceManager deployed to: %s", address(nonceManager));

        walletImplementation = new QuarkWallet(codeJar, nonceManager);
        console.log("QuarkWallet implementation: %s", address(walletImplementation));

        aliceWallet = newWallet(aliceAccount, address(0));
        console.log("Alice signer: %s", aliceAccount);
        console.log("Alice wallet at: %s", address(aliceWallet));
    }

    /* ===== immutable getters tests ===== */

    function testGetSigner() public {
        assertEq(IHasSignerExecutor(address(aliceWallet)).signer(), aliceAccount);
    }

    function testGetExecutor() public {
        assertEq(IHasSignerExecutor(address(aliceWallet)).executor(), address(0));
    }

    function testGetCodeJar() public {
        assertEq(address(aliceWallet.codeJar()), address(codeJar));
    }

    function testGetNonceManager() public {
        assertEq(address(aliceWallet.nonceManager()), address(nonceManager));
    }

    /* ===== msg.value and msg.sender tests ===== */

    function testSetsMsgSender() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory getMessageDetails = new YulHelper().getCode("GetMessageDetails.sol/GetMessageDetails.json");
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
        bytes memory getMessageDetails = new YulHelper().getCode("GetMessageDetails.sol/GetMessageDetails.json");
        bytes32 nonce = new QuarkOperationHelper().semiRandomNonce(nonceManager, aliceWalletExecutable);
        address scriptAddress = codeJar.saveCode(getMessageDetails);
        bytes memory call = abi.encodeWithSignature("getMsgSenderAndValue()");

        vm.startPrank(aliceAccount);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWalletExecutable.executeScript(nonce, scriptAddress, call, new bytes[](0));

        vm.stopPrank();

        (address msgSender, uint256 msgValue) = abi.decode(result, (address, uint256));
        assertEq(msgSender, address(aliceWalletExecutable));
        assertEq(msgValue, 0);
    }

    /* ===== event emission tests ===== */

    function testEmitsEventsInExecuteQuarkOperation() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory getMessageDetails = new YulHelper().getCode("GetMessageDetails.sol/GetMessageDetails.json");
        QuarkWallet.QuarkOperation memory opWithScriptAddress = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet, getMessageDetails, abi.encodeWithSignature("getMsgSenderAndValue()"), ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) =
            new SignatureHelper().signOp(alicePrivateKey, aliceWallet, opWithScriptAddress);
        QuarkWallet.QuarkOperation memory opWithScriptSource = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet, getMessageDetails, abi.encodeWithSignature("getMsgSenderAndValue()"), ScriptType.ScriptSource
        );
        opWithScriptSource.nonce = new QuarkOperationHelper().incrementNonce(opWithScriptSource.nonce);
        (uint8 v2, bytes32 r2, bytes32 s2) =
            new SignatureHelper().signOp(alicePrivateKey, aliceWallet, opWithScriptSource);
        address scriptAddress = opWithScriptAddress.scriptAddress;

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectEmit(true, true, true, true);
        emit ExecuteQuarkScript(
            address(this), scriptAddress, opWithScriptAddress.nonce, opWithScriptAddress.nonce, ExecutionType.Signature
        );
        aliceWallet.executeQuarkOperation(opWithScriptAddress, v, r, s);

        vm.expectEmit(true, true, true, true);
        emit ExecuteQuarkScript(
            address(this), scriptAddress, opWithScriptSource.nonce, opWithScriptSource.nonce, ExecutionType.Signature
        );
        aliceWallet.executeQuarkOperation(opWithScriptSource, v2, r2, s2);
    }

    function testEmitsEventsInReplayableQuarkOperation() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory getMessageDetails = new YulHelper().getCode("GetMessageDetails.sol/GetMessageDetails.json");
        (QuarkWallet.QuarkOperation memory opWithScriptAddress, bytes32[] memory submissionTokens) = new QuarkOperationHelper(
        ).newReplayableOpWithCalldata(
            aliceWallet,
            getMessageDetails,
            abi.encodeWithSignature("getMsgSenderAndValue()"),
            ScriptType.ScriptAddress,
            2
        );
        address scriptAddress = opWithScriptAddress.scriptAddress;
        (uint8 v, bytes32 r, bytes32 s) =
            new SignatureHelper().signOp(alicePrivateKey, aliceWallet, opWithScriptAddress);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectEmit(true, true, true, true);
        emit ExecuteQuarkScript(
            address(this), scriptAddress, opWithScriptAddress.nonce, opWithScriptAddress.nonce, ExecutionType.Signature
        );
        aliceWallet.executeQuarkOperation(opWithScriptAddress, v, r, s);

        // second execution
        vm.expectEmit(true, true, true, true);
        emit ExecuteQuarkScript(
            address(this), scriptAddress, opWithScriptAddress.nonce, submissionTokens[1], ExecutionType.Signature
        );
        aliceWallet.executeQuarkOperationWithSubmissionToken(opWithScriptAddress, submissionTokens[1], v, r, s);

        // third execution
        vm.expectEmit(true, true, true, true);
        emit ExecuteQuarkScript(
            address(this), scriptAddress, opWithScriptAddress.nonce, submissionTokens[2], ExecutionType.Signature
        );
        aliceWallet.executeQuarkOperationWithSubmissionToken(opWithScriptAddress, submissionTokens[2], v, r, s);
    }

    function testEmitsEventsInDirectExecute() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        QuarkWallet aliceWalletExecutable = newWallet(aliceAccount, aliceAccount);
        bytes memory getMessageDetails = new YulHelper().getCode("GetMessageDetails.sol/GetMessageDetails.json");
        bytes32 nonce = new QuarkOperationHelper().semiRandomNonce(nonceManager, aliceWalletExecutable);
        address scriptAddress = codeJar.saveCode(getMessageDetails);
        bytes memory call = abi.encodeWithSignature("getMsgSenderAndValue()");

        vm.startPrank(aliceAccount);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectEmit(true, true, true, true);
        emit ExecuteQuarkScript(address(aliceAccount), scriptAddress, nonce, nonce, ExecutionType.Direct);
        aliceWalletExecutable.executeScript(nonce, scriptAddress, call, new bytes[](0));
    }

    function testFailsWithRepeatNonceInDirectExecute() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();

        assertEq(counter.number(), 0);

        bytes memory maxCounterScript = new YulHelper().getCode("MaxCounterScript.sol/MaxCounterScript.json");
        address scriptAddress = codeJar.saveCode(maxCounterScript);
        bytes memory call = abi.encodeWithSignature("run(address)", address(counter));

        QuarkWallet aliceWalletExecutable = newWallet(aliceAccount, aliceAccount);
        bytes32 nonce = new QuarkOperationHelper().semiRandomNonce(nonceManager, aliceWalletExecutable);

        vm.startPrank(aliceAccount);

        bytes[] memory scriptSources = new bytes[](0);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectEmit(true, true, true, true);
        emit ExecuteQuarkScript(address(aliceAccount), scriptAddress, nonce, nonce, ExecutionType.Direct);
        aliceWalletExecutable.executeScript(nonce, scriptAddress, call, scriptSources);

        assertEq(counter.number(), 1);

        // TODO: Diagnose why this revert isn't causing a general revert
        // Not sure why this revert isn't showing up-- it's reverting, nonetheless.
        // vm.expectRevert(
        //     abi.encodeWithSelector(
        //         QuarkNonceManager.NonReplayableNonce.selector, address(aliceWalletExecutable), nonce, nonce, true
        //     )
        // );
        aliceWalletExecutable.executeScript(nonce, scriptAddress, call, scriptSources);
        assertEq(counter.number(), 1);
    }

    /* ===== general invariant tests ===== */

    function testRequiresCorrectSubmissionToken() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();

        bytes memory getMessageDetails = new YulHelper().getCode("GetMessageDetails.sol/GetMessageDetails.json");
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet, getMessageDetails, abi.encodeWithSignature("getMsgSenderAndValue()"), ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();

        // pass in invalid submission tokens
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, aliceWallet, op.nonce, bytes32(0))
        );
        aliceWallet.executeQuarkOperationWithSubmissionToken(op, bytes32(0), v, r, s);

        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, aliceWallet, op.nonce, bytes32(uint256(1))
            )
        );
        aliceWallet.executeQuarkOperationWithSubmissionToken(op, bytes32(uint256(1)), v, r, s);

        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, aliceWallet, op.nonce, EXHAUSTED_TOKEN
            )
        );
        aliceWallet.executeQuarkOperationWithSubmissionToken(op, EXHAUSTED_TOKEN, v, r, s);

        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, aliceWallet, op.nonce, bytes32(uint256(op.nonce) + 1)
            )
        );
        aliceWallet.executeQuarkOperationWithSubmissionToken(op, bytes32(uint256(op.nonce) + 1), v, r, s);

        // Run script
        aliceWallet.executeQuarkOperationWithSubmissionToken(op, op.nonce, v, r, s);

        // Check it is no longer runnable
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.NonReplayableNonce.selector, address(aliceWallet), op.nonce, op.nonce, true
            )
        );
        aliceWallet.executeQuarkOperationWithSubmissionToken(op, op.nonce, v, r, s);
    }

    function testDisallowAllNullScriptAddress() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            nonce: new QuarkOperationHelper().semiRandomNonce(nonceManager, aliceWallet),
            isReplayable: false,
            scriptAddress: address(0),
            scriptSources: new bytes[](0),
            scriptCalldata: bytes(""),
            expiry: block.timestamp + 1000
        });
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();

        // operation containing no script will revert
        vm.expectRevert(abi.encodeWithSelector(QuarkWallet.EmptyCode.selector));
        aliceWallet.executeQuarkOperation(op, v, r, s);

        // direct execution of the null script will revert
        bytes32 nonce = new QuarkOperationHelper().semiRandomNonce(nonceManager, aliceWallet);
        vm.prank(IHasSignerExecutor(address(aliceWallet)).executor());
        vm.expectRevert(abi.encodeWithSelector(QuarkWallet.EmptyCode.selector));
        aliceWallet.executeScript(nonce, address(0), bytes(""), new bytes[](0));

        // gas: do not meter set-up
        vm.pauseGasMetering();

        // NOTE: we cannot deploy the empty code with codeJar, it will revert.
        address emptyCodeAddress = address(new EmptyCode());

        // operation containing a valid empty script will revert
        QuarkWallet.QuarkOperation memory op2 = QuarkWallet.QuarkOperation({
            nonce: new QuarkOperationHelper().semiRandomNonce(nonceManager, aliceWallet),
            isReplayable: false,
            scriptAddress: emptyCodeAddress,
            scriptSources: new bytes[](0),
            scriptCalldata: bytes(""),
            expiry: block.timestamp + 1000
        });
        (uint8 v2, bytes32 r2, bytes32 s2) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op2);

        // gas: meter execute
        vm.resumeGasMetering();

        // operation on empty script will revert
        vm.expectRevert(abi.encodeWithSelector(QuarkWallet.EmptyCode.selector));
        aliceWallet.executeQuarkOperation(op2, v2, r2, s2);

        // direct execution of empty script will revert
        bytes32 nonce2 = new QuarkOperationHelper().semiRandomNonce(nonceManager, aliceWallet);
        vm.prank(IHasSignerExecutor(address(aliceWallet)).executor());
        vm.expectRevert(abi.encodeWithSelector(QuarkWallet.EmptyCode.selector));
        aliceWallet.executeScript(nonce2, emptyCodeAddress, bytes(""), new bytes[](0));
    }

    function testRevertsForRandomEmptyScriptAddress() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();

        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = new YulHelper().stub(hex"f00f00");

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            nonce: new QuarkOperationHelper().semiRandomNonce(nonceManager, aliceWallet),
            isReplayable: false,
            scriptAddress: address(0xc0c0),
            scriptSources: scriptSources,
            scriptCalldata: bytes("feefee"),
            expiry: block.timestamp + 1000
        });
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();

        vm.expectRevert(abi.encodeWithSelector(QuarkWallet.EmptyCode.selector));
        aliceWallet.executeQuarkOperation(op, v, r, s);
    }

    /* ===== storage tests ===== */

    function testReadStorageForWallet() public {
        // gas: disable metering except while executing operations
        vm.pauseGasMetering();

        assertEq(counter.number(), 0);

        bytes memory maxCounter = new YulHelper().getCode("MaxCounterScript.sol/MaxCounterScript.json");

        (QuarkWallet.QuarkOperation memory op, bytes32[] memory submissionTokens) = new QuarkOperationHelper()
            .newReplayableOpWithCalldata(
            aliceWallet,
            maxCounter,
            abi.encodeWithSignature("run(address)", address(counter)),
            ScriptType.ScriptAddress,
            4
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        assertEq(
            vm.load(address(aliceWallet), keccak256(abi.encodePacked(op.nonce, keccak256("count")))),
            bytes32(uint256(0))
        );

        vm.resumeGasMetering();

        aliceWallet.executeQuarkOperationWithSubmissionToken(op, submissionTokens[0], v, r, s);
        assertEq(
            vm.load(address(aliceWallet), keccak256(abi.encodePacked(op.nonce, keccak256("count")))),
            bytes32(uint256(1))
        );
        assertEq(counter.number(), 1);

        aliceWallet.executeQuarkOperationWithSubmissionToken(op, submissionTokens[1], v, r, s);
        assertEq(
            vm.load(address(aliceWallet), keccak256(abi.encodePacked(op.nonce, keccak256("count")))),
            bytes32(uint256(2))
        );
        assertEq(counter.number(), 2);

        aliceWallet.executeQuarkOperationWithSubmissionToken(op, submissionTokens[2], v, r, s);
        assertEq(
            vm.load(address(aliceWallet), keccak256(abi.encodePacked(op.nonce, keccak256("count")))),
            bytes32(uint256(3))
        );
        assertEq(counter.number(), 3);

        vm.expectRevert(abi.encodeWithSelector(MaxCounterScript.EnoughAlready.selector));
        aliceWallet.executeQuarkOperationWithSubmissionToken(op, submissionTokens[3], v, r, s);
        assertEq(
            vm.load(address(aliceWallet), keccak256(abi.encodePacked(op.nonce, keccak256("count")))),
            bytes32(uint256(3))
        );
        assertEq(counter.number(), 3);
    }

    /* ===== replayability tests ===== */

    function testCanReplaySameScriptWithDifferentCall() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");

        // 1. use nonce to increment a counter
        (QuarkWallet.QuarkOperation memory op1, bytes32[] memory submissionTokens) = new QuarkOperationHelper()
            .newReplayableOpWithCalldata(
            aliceWallet,
            incrementer,
            abi.encodeWithSignature("incrementCounter(address)", address(counter)),
            ScriptType.ScriptAddress,
            1
        );
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op1);

        address incrementerAddress = codeJar.saveCode(incrementer);

        QuarkWallet.QuarkOperation memory op2 = QuarkWallet.QuarkOperation({
            nonce: op1.nonce,
            isReplayable: true,
            scriptAddress: incrementerAddress,
            scriptSources: new bytes[](0),
            scriptCalldata: abi.encodeWithSignature("incrementCounter2(address)", address(counter)),
            expiry: block.timestamp + 1000
        });
        (uint8 v2, bytes32 r2, bytes32 s2) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op2);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op1, v1, r1, s1);
        // incrementer increments the counter thrice
        assertEq(counter.number(), 3);
        // when executing a replayable operation, you can change the call
        aliceWallet.executeQuarkOperationWithSubmissionToken(op2, submissionTokens[1], v2, r2, s2);
        // incrementer increments the counter frice
        assertEq(counter.number(), 7);
        // but now both operations are exhausted
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, aliceWallet, op1.nonce, op1.nonce)
        );
        aliceWallet.executeQuarkOperation(op1, v1, r1, s1);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, aliceWallet, op1.nonce, submissionTokens[1]
            )
        );
        aliceWallet.executeQuarkOperationWithSubmissionToken(op1, submissionTokens[1], v1, r1, s1);
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, aliceWallet, op1.nonce, op2.nonce)
        );
        aliceWallet.executeQuarkOperation(op2, v2, r2, s2);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, aliceWallet, op1.nonce, submissionTokens[1]
            )
        );
        aliceWallet.executeQuarkOperationWithSubmissionToken(op2, submissionTokens[1], v2, r2, s2);
    }

    function testAllowsForReusedNonceWithChangedScript() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");
        bytes memory incrementerBySix = new YulHelper().getCode("Incrementer.sol/IncrementerBySix.json");

        // 1. use nonce to increment a counter
        (QuarkWallet.QuarkOperation memory op1, bytes32[] memory submissionTokens) = new QuarkOperationHelper()
            .newReplayableOpWithCalldata(
            aliceWallet,
            incrementer,
            abi.encodeWithSignature("incrementCounter(address)", address(counter)),
            ScriptType.ScriptAddress,
            1
        );
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op1);

        QuarkWallet.QuarkOperation memory op2 = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            incrementerBySix,
            abi.encodeWithSignature("incrementCounter(address)", address(counter)),
            ScriptType.ScriptAddress
        );
        op2.nonce = op1.nonce;
        (uint8 v2, bytes32 r2, bytes32 s2) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op2);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op1, v1, r1, s1);
        // incrementer increments the counter thrice
        assertEq(counter.number(), 3);
        // when reusing the nonce but changing the script, allow
        aliceWallet.executeQuarkOperationWithSubmissionToken(op2, submissionTokens[1], v2, r2, s2);
        // updated with larger incrementer script
        assertEq(counter.number(), 9);
    }

    function testScriptCanBeCanceledByNoOp() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");

        (QuarkWallet.QuarkOperation memory op, bytes32[] memory submissionTokens) = new QuarkOperationHelper()
            .newReplayableOpWithCalldata(
            aliceWallet,
            incrementer,
            abi.encodeWithSignature("incrementCounter(address)", address(counter)),
            ScriptType.ScriptAddress,
            1
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op, v, r, s);
        assertEq(counter.number(), 3);
        // cannot replay the same operation directly...
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, aliceWallet, op.nonce, op.nonce)
        );
        aliceWallet.executeQuarkOperation(op, v, r, s);
        assertEq(counter.number(), 3);

        // can cancel the replayable nonce...
        vm.pauseGasMetering();
        QuarkWallet.QuarkOperation memory cancelOtherOp =
            new QuarkOperationHelper().cancelReplayableByNop(aliceWallet, op);
        (uint8 cancelV, bytes32 cancelR, bytes32 cancelS) =
            new SignatureHelper().signOp(alicePrivateKey, aliceWallet, cancelOtherOp);
        vm.resumeGasMetering();
        vm.expectEmit(true, true, true, true);
        emit CancelOtherScript.Nop();
        aliceWallet.executeQuarkOperationWithSubmissionToken(
            cancelOtherOp, submissionTokens[1], cancelV, cancelR, cancelS
        );

        // and now you can no longer replay
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.NonReplayableNonce.selector, address(aliceWallet), op.nonce, submissionTokens[1], true
            )
        );
        aliceWallet.executeQuarkOperationWithSubmissionToken(op, submissionTokens[1], v, r, s);

        // Ensure exhausted
        assertEq(nonceManager.submissions(address(aliceWallet), op.nonce), bytes32(type(uint256).max));
    }

    function testScriptCanBeCanceledByNewOp() public {
        // gas: disable gas metering except while executing operations
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");

        (QuarkWallet.QuarkOperation memory op, bytes32[] memory submissionTokens) = new QuarkOperationHelper()
            .newReplayableOpWithCalldata(
            aliceWallet,
            incrementer,
            abi.encodeWithSignature("incrementCounter(address)", address(counter)),
            ScriptType.ScriptAddress,
            1
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op, v, r, s);
        assertEq(counter.number(), 3);
        // cannot replay the same operation directly...
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, aliceWallet, op.nonce, op.nonce)
        );
        aliceWallet.executeQuarkOperation(op, v, r, s);
        assertEq(counter.number(), 3);

        // can cancel the replayable nonce...
        vm.pauseGasMetering();
        QuarkWallet.QuarkOperation memory cancelOtherOp =
            new QuarkOperationHelper().cancelReplayableByNewOp(aliceWallet, op);
        (uint8 cancelV, bytes32 cancelR, bytes32 cancelS) =
            new SignatureHelper().signOp(alicePrivateKey, aliceWallet, cancelOtherOp);
        vm.resumeGasMetering();
        vm.expectEmit(true, true, true, true);
        emit CancelOtherScript.CancelNonce(op.nonce);
        aliceWallet.executeQuarkOperationWithSubmissionToken(
            cancelOtherOp, submissionTokens[1], cancelV, cancelR, cancelS
        );

        // and now you can no longer replay
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.NonReplayableNonce.selector, address(aliceWallet), op.nonce, submissionTokens[1], true
            )
        );
        aliceWallet.executeQuarkOperationWithSubmissionToken(op, submissionTokens[1], v, r, s);

        // Ensure exhausted
        assertEq(nonceManager.submissions(address(aliceWallet), op.nonce), bytes32(type(uint256).max));
    }

    /* ===== direct execution path tests ===== */

    function testDirectExecuteFromEOA() public {
        // gas: disable metering except while executing operations
        vm.pauseGasMetering();
        QuarkWallet aliceWalletExecutable = newWallet(aliceAccount, aliceAccount);
        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");
        address incrementerAddress = codeJar.saveCode(incrementer);
        bytes32 nonce = new QuarkOperationHelper().semiRandomNonce(nonceManager, aliceWalletExecutable);
        bytes memory call = abi.encodeWithSignature("incrementCounter(address)", counter);

        assertEq(counter.number(), 0);
        assertEq(nonceManager.submissions(address(aliceWalletExecutable), nonce), bytes32(uint256(0)));

        // act as the executor for the wallet
        vm.startPrank(aliceAccount);

        bytes[] memory scriptSources = new bytes[](0);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWalletExecutable.executeScript(nonce, incrementerAddress, call, scriptSources);

        assertEq(counter.number(), 3);
        assertEq(nonceManager.submissions(address(aliceWalletExecutable), nonce), bytes32(type(uint256).max));
    }

    function testDirectExecuteFromOtherQuarkWallet() public {
        // gas: disable metering except while executing operations
        vm.pauseGasMetering();
        QuarkWallet aliceWalletExecutable = newWallet(aliceAccount, address(aliceWallet));
        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");
        bytes memory ethcall = new YulHelper().getCode("Ethcall.sol/Ethcall.json");
        address incrementerAddress = codeJar.saveCode(incrementer);
        bytes32 nonce = new QuarkOperationHelper().semiRandomNonce(nonceManager, aliceWalletExecutable);
        bytes memory ethcallCalldata = abi.encodeWithSelector(
            Ethcall.run.selector,
            address(aliceWalletExecutable),
            abi.encodeWithSignature(
                "executeScript(bytes32,address,bytes,bytes[])",
                nonce,
                incrementerAddress,
                abi.encodeWithSignature("incrementCounter(address)", counter),
                new bytes[](0)
            ),
            0 // value
        );

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet, ethcall, ethcallCalldata, ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        assertEq(counter.number(), 0);
        assertEq(nonceManager.submissions(address(aliceWalletExecutable), nonce), bytes32(uint256(0)));

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op, v, r, s);

        assertEq(counter.number(), 3);
        assertEq(nonceManager.submissions(address(aliceWalletExecutable), nonce), bytes32(type(uint256).max));
    }

    function testDirectExecuteWithScriptSources() public {
        // gas: disable metering except while executing operations
        vm.pauseGasMetering();
        QuarkWallet aliceWalletExecutable = newWallet(aliceAccount, aliceAccount);
        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");
        address incrementerAddress = codeJar.getCodeAddress(incrementer);
        bytes32 nonce = new QuarkOperationHelper().semiRandomNonce(nonceManager, aliceWalletExecutable);
        bytes memory call = abi.encodeWithSignature("incrementCounter(address)", counter);
        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = incrementer;

        assertEq(counter.number(), 0);
        assertEq(nonceManager.submissions(address(aliceWalletExecutable), nonce), bytes32(uint256(0)));

        // act as the executor for the wallet
        vm.startPrank(aliceAccount);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWalletExecutable.executeScript(nonce, incrementerAddress, call, scriptSources);

        assertEq(counter.number(), 3);
        assertEq(nonceManager.submissions(address(aliceWalletExecutable), nonce), bytes32(type(uint256).max));
    }

    function testRevertsForDirectExecuteByNonExecutorSigner() public {
        // gas: disable metering except while executing operations
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");
        assertEq(counter.number(), 0);

        // act as the signer for the wallet
        vm.startPrank(IHasSignerExecutor(address(aliceWallet)).signer());

        // pre-compute execution parameters so that the revert is expected from the right call
        bytes32 nonce = new QuarkOperationHelper().semiRandomNonce(nonceManager, aliceWallet);
        address target = codeJar.saveCode(incrementer);
        bytes memory call = abi.encodeWithSignature("incrementCounter(address)", counter);

        // gas: meter execute
        vm.resumeGasMetering();

        vm.expectRevert(abi.encodeWithSelector(QuarkWallet.Unauthorized.selector));
        aliceWallet.executeScript(nonce, target, call, new bytes[](0));

        vm.stopPrank();

        assertEq(counter.number(), 0);
    }

    function testRevertsForUnauthorizedDirectExecuteByRandomAddress() public {
        // gas: disable metering except while executing operations
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");
        assertEq(counter.number(), 0);

        // pre-compute execution parameters so that the revert is expected from the right call
        bytes32 nonce = new QuarkOperationHelper().semiRandomNonce(nonceManager, aliceWallet);
        address target = codeJar.saveCode(incrementer);
        bytes memory call = abi.encodeWithSignature("incrementCounter(address)", counter);

        // some arbitrary address cannot execute scripts directly on alice's wallet
        vm.startPrank(address(0xf00f00b47b47));

        // gas: meter execute
        vm.resumeGasMetering();

        vm.expectRevert(abi.encodeWithSelector(QuarkWallet.Unauthorized.selector));
        aliceWallet.executeScript(nonce, target, call, new bytes[](0));

        vm.stopPrank();

        assertEq(counter.number(), 0);
    }

    /* ===== MultiQuarkOperation execution path tests ===== */

    function testMultiQuarkOperationCanCallMultipleOperationsWithOneSignature() public {
        // gas: disable metering except while executing operations
        vm.pauseGasMetering();

        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");
        assertEq(counter.number(), 0);

        vm.startPrank(address(aliceAccount));

        QuarkWallet.QuarkOperation memory op1 = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            incrementer,
            abi.encodeWithSignature("incrementCounter(address)", counter),
            ScriptType.ScriptAddress
        );
        bytes32 op1Digest = new SignatureHelper().opDigest(address(aliceWallet), op1);

        QuarkWallet.QuarkOperation memory op2 = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            incrementer,
            abi.encodeWithSignature("incrementCounter(address)", counter),
            ScriptType.ScriptAddress
        );
        op2.nonce = new QuarkOperationHelper().incrementNonce(op1.nonce);
        bytes32 op2Digest = new SignatureHelper().opDigest(address(aliceWallet), op2);

        bytes32[] memory opDigests = new bytes32[](2);
        opDigests[0] = op1Digest;
        opDigests[1] = op2Digest;
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signMultiOp(alicePrivateKey, opDigests);

        // call once
        vm.resumeGasMetering();
        aliceWallet.executeMultiQuarkOperation(op1, opDigests, v, r, s);

        assertEq(counter.number(), 3);

        // call a second time
        aliceWallet.executeMultiQuarkOperation(op2, opDigests, v, r, s);

        assertEq(counter.number(), 6);
    }

    function testRevertsForBadInputsInMultiQuarkOperation() public {
        // gas: disable metering except while executing operations
        vm.pauseGasMetering();

        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");
        assertEq(counter.number(), 0);

        vm.startPrank(address(aliceAccount));

        QuarkWallet.QuarkOperation memory op1 = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            incrementer,
            abi.encodeWithSignature("incrementCounter(address)", counter),
            ScriptType.ScriptAddress
        );
        bytes32 op1Digest = new SignatureHelper().opDigest(address(aliceWallet), op1);

        QuarkWallet.QuarkOperation memory op2 = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            incrementer,
            abi.encodeWithSignature("incrementCounter(address)", counter),
            ScriptType.ScriptAddress
        );
        op2.nonce = new QuarkOperationHelper().incrementNonce(op1.nonce);

        bytes32[] memory opDigests = new bytes32[](1);
        opDigests[0] = op1Digest;
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signMultiOp(alicePrivateKey, opDigests);

        // call with operation that is not part of opDigests
        vm.resumeGasMetering();
        vm.expectRevert(abi.encodeWithSelector(QuarkWallet.InvalidMultiQuarkOperation.selector));
        aliceWallet.executeMultiQuarkOperation(op2, opDigests, v, r, s);

        assertEq(counter.number(), 0);
    }

    function testRevertsForNonceReuse() public {
        // gas: disable metering except while executing operations
        vm.pauseGasMetering();

        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");
        assertEq(counter.number(), 0);

        vm.startPrank(address(aliceAccount));

        QuarkWallet.QuarkOperation memory op1 = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            incrementer,
            abi.encodeWithSignature("incrementCounter(address)", counter),
            ScriptType.ScriptAddress
        );
        bytes32 op1Digest = new SignatureHelper().opDigest(address(aliceWallet), op1);

        QuarkWallet.QuarkOperation memory op2 = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            incrementer,
            abi.encodeWithSignature("incrementCounter(address)", counter),
            ScriptType.ScriptAddress
        );
        op2.nonce = new QuarkOperationHelper().incrementNonce(op1.nonce);
        bytes32 op2Digest = new SignatureHelper().opDigest(address(aliceWallet), op2);

        bytes32[] memory opDigests = new bytes32[](2);
        opDigests[0] = op1Digest;
        opDigests[1] = op2Digest;
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signMultiOp(alicePrivateKey, opDigests);

        // call once
        vm.resumeGasMetering();
        aliceWallet.executeMultiQuarkOperation(op1, opDigests, v, r, s);

        assertEq(counter.number(), 3);

        // call again using the same operation
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.NonReplayableNonce.selector, address(aliceWallet), op1.nonce, op1.nonce, true
            )
        );
        aliceWallet.executeMultiQuarkOperation(op1, opDigests, v, r, s);

        assertEq(counter.number(), 3);
    }

    function testReplayableMultiQuarkOperation() public {
        // gas: disable metering except while executing operations
        vm.pauseGasMetering();

        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");
        assertEq(counter.number(), 0);

        (QuarkWallet.QuarkOperation memory op1, bytes32[] memory submissionTokens1) = new QuarkOperationHelper()
            .newReplayableOpWithCalldata(
            aliceWallet,
            incrementer,
            abi.encodeWithSignature("incrementCounter(address)", counter),
            ScriptType.ScriptAddress,
            2
        );
        bytes32 op1Digest = new SignatureHelper().opDigest(address(aliceWallet), op1);

        (QuarkWallet.QuarkOperation memory op2, bytes32[] memory submissionTokens2) = new QuarkOperationHelper()
            .newReplayableOpWithCalldata(
            aliceWallet,
            incrementer,
            abi.encodeWithSignature("incrementCounter2(address)", counter),
            ScriptType.ScriptAddress,
            2,
            new QuarkOperationHelper().incrementNonce(op1.nonce)
        );
        bytes32 op2Digest = new SignatureHelper().opDigest(address(aliceWallet), op2);

        bytes32[] memory opDigests = new bytes32[](2);
        opDigests[0] = op1Digest;
        opDigests[1] = op2Digest;
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signMultiOp(alicePrivateKey, opDigests);

        vm.resumeGasMetering();

        // call op1, first
        assertEq(nonceManager.submissions(address(aliceWallet), op1.nonce), bytes32(0));
        aliceWallet.executeMultiQuarkOperation(op1, opDigests, v, r, s);
        assertEq(counter.number(), 3);
        assertEq(nonceManager.submissions(address(aliceWallet), op1.nonce), op1.nonce);

        // call op2, first
        assertEq(nonceManager.submissions(address(aliceWallet), op2.nonce), bytes32(0));
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op2, submissionTokens2[0], opDigests, v, r, s);
        assertEq(counter.number(), 7);
        assertEq(nonceManager.submissions(address(aliceWallet), op2.nonce), op2.nonce);

        // call op1, second
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op1, submissionTokens1[1], opDigests, v, r, s);
        assertEq(counter.number(), 10);
        assertEq(nonceManager.submissions(address(aliceWallet), op1.nonce), submissionTokens1[1]);

        // call op1, third
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op1, submissionTokens1[2], opDigests, v, r, s);
        assertEq(counter.number(), 13);

        // test all tokens do not replay now for op1
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, aliceWallet, op1.nonce, EXHAUSTED_TOKEN
            )
        );
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op1, EXHAUSTED_TOKEN, opDigests, v, r, s);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, aliceWallet, op1.nonce, submissionTokens1[0]
            )
        );
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op1, submissionTokens1[0], opDigests, v, r, s);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, aliceWallet, op1.nonce, submissionTokens1[1]
            )
        );
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op1, submissionTokens1[1], opDigests, v, r, s);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, aliceWallet, op1.nonce, submissionTokens1[2]
            )
        );
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op1, submissionTokens1[2], opDigests, v, r, s);

        // call op2, second
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op2, submissionTokens2[1], opDigests, v, r, s);
        assertEq(counter.number(), 17);

        // call op2, third
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op2, submissionTokens2[2], opDigests, v, r, s);
        assertEq(counter.number(), 21);

        // test all tokens do not replay now for op2
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, aliceWallet, op2.nonce, EXHAUSTED_TOKEN
            )
        );
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op2, EXHAUSTED_TOKEN, opDigests, v, r, s);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, aliceWallet, op2.nonce, submissionTokens2[0]
            )
        );
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op2, submissionTokens2[0], opDigests, v, r, s);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, aliceWallet, op2.nonce, submissionTokens2[1]
            )
        );
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op2, submissionTokens2[1], opDigests, v, r, s);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, aliceWallet, op2.nonce, submissionTokens2[2]
            )
        );
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op2, submissionTokens2[2], opDigests, v, r, s);
    }

    function testHalfReplayableMultiQuarkOperation() public {
        // gas: disable metering except while executing operations
        vm.pauseGasMetering();

        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");
        assertEq(counter.number(), 0);

        QuarkWallet.QuarkOperation memory op1 = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            incrementer,
            abi.encodeWithSignature("incrementCounter(address)", counter),
            ScriptType.ScriptAddress
        );
        bytes32 op1Digest = new SignatureHelper().opDigest(address(aliceWallet), op1);

        (QuarkWallet.QuarkOperation memory op2, bytes32[] memory submissionTokens2) = new QuarkOperationHelper()
            .newReplayableOpWithCalldata(
            aliceWallet,
            incrementer,
            abi.encodeWithSignature("incrementCounter2(address)", counter),
            ScriptType.ScriptAddress,
            2,
            new QuarkOperationHelper().incrementNonce(op1.nonce)
        );
        bytes32 op2Digest = new SignatureHelper().opDigest(address(aliceWallet), op2);

        bytes32[] memory opDigests = new bytes32[](2);
        opDigests[0] = op1Digest;
        opDigests[1] = op2Digest;
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signMultiOp(alicePrivateKey, opDigests);

        vm.resumeGasMetering();

        // call op1
        assertEq(nonceManager.submissions(address(aliceWallet), op1.nonce), bytes32(0));
        aliceWallet.executeMultiQuarkOperation(op1, opDigests, v, r, s);
        assertEq(counter.number(), 3);
        assertEq(nonceManager.submissions(address(aliceWallet), op1.nonce), EXHAUSTED_TOKEN);

        // call op2, first
        assertEq(nonceManager.submissions(address(aliceWallet), op2.nonce), bytes32(0));
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op2, submissionTokens2[0], opDigests, v, r, s);
        assertEq(counter.number(), 7);
        assertEq(nonceManager.submissions(address(aliceWallet), op2.nonce), op2.nonce);

        // test all tokens do not replay now for op1, which is non-replayable
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.NonReplayableNonce.selector, aliceWallet, op1.nonce, EXHAUSTED_TOKEN, true
            )
        );
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op1, EXHAUSTED_TOKEN, opDigests, v, r, s);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.NonReplayableNonce.selector, aliceWallet, op1.nonce, op1.nonce, true
            )
        );
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op1, op1.nonce, opDigests, v, r, s);

        // call op2, second
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op2, submissionTokens2[1], opDigests, v, r, s);
        assertEq(counter.number(), 11);

        // call op2, third
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op2, submissionTokens2[2], opDigests, v, r, s);
        assertEq(counter.number(), 15);

        // test all tokens do not replay now for op2
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, aliceWallet, op2.nonce, EXHAUSTED_TOKEN
            )
        );
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op2, EXHAUSTED_TOKEN, opDigests, v, r, s);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, aliceWallet, op2.nonce, submissionTokens2[0]
            )
        );
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op2, submissionTokens2[0], opDigests, v, r, s);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, aliceWallet, op2.nonce, submissionTokens2[1]
            )
        );
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op2, submissionTokens2[1], opDigests, v, r, s);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, aliceWallet, op2.nonce, submissionTokens2[2]
            )
        );
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op2, submissionTokens2[2], opDigests, v, r, s);
    }

    function testReplayableMultiQuarkOperationWithSharedNonce() public {
        // gas: disable metering except while executing operations
        vm.pauseGasMetering();

        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");
        assertEq(counter.number(), 0);

        (QuarkWallet.QuarkOperation memory op1, bytes32[] memory submissionTokens1) = new QuarkOperationHelper()
            .newReplayableOpWithCalldata(
            aliceWallet,
            incrementer,
            abi.encodeWithSignature("incrementCounter(address)", counter),
            ScriptType.ScriptAddress,
            2
        );
        bytes32 op1Digest = new SignatureHelper().opDigest(address(aliceWallet), op1);

        (QuarkWallet.QuarkOperation memory op2, bytes32[] memory submissionTokens2) = new QuarkOperationHelper()
            .newReplayableOpWithCalldata(
            aliceWallet,
            incrementer,
            abi.encodeWithSignature("incrementCounter2(address)", counter),
            ScriptType.ScriptAddress,
            2,
            submissionTokens1[2] // Same nonce secret
        );
        bytes32 op2Digest = new SignatureHelper().opDigest(address(aliceWallet), op2);

        bytes32[] memory opDigests = new bytes32[](2);
        opDigests[0] = op1Digest;
        opDigests[1] = op2Digest;
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signMultiOp(alicePrivateKey, opDigests);

        vm.resumeGasMetering();

        // call op1, first
        assertEq(nonceManager.submissions(address(aliceWallet), op1.nonce), bytes32(0));
        aliceWallet.executeMultiQuarkOperation(op1, opDigests, v, r, s);
        assertEq(counter.number(), 3);
        assertEq(nonceManager.submissions(address(aliceWallet), op1.nonce), op1.nonce);

        // ensure op1 and op2 submissions fail on submissionTokens[0]
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, aliceWallet, op2.nonce, submissionTokens2[0]
            )
        );
        aliceWallet.executeMultiQuarkOperation(op2, opDigests, v, r, s);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, aliceWallet, op2.nonce, submissionTokens2[0]
            )
        );
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op2, submissionTokens2[0], opDigests, v, r, s);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, aliceWallet, op2.nonce, submissionTokens1[0]
            )
        );
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op1, submissionTokens1[0], opDigests, v, r, s);

        // now submit op2 with submissionTokens[1]
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op2, submissionTokens2[1], opDigests, v, r, s);
        assertEq(counter.number(), 7);

        // ensure neither can be called with submissionTokens[1] now
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, aliceWallet, op2.nonce, submissionTokens2[1]
            )
        );
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op2, submissionTokens2[1], opDigests, v, r, s);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, aliceWallet, op2.nonce, submissionTokens1[1]
            )
        );
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op1, submissionTokens1[1], opDigests, v, r, s);

        // call op1, third
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op1, submissionTokens1[2], opDigests, v, r, s);
        assertEq(counter.number(), 10);

        // ensure neither can be called with submissionTokens[2] now
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, aliceWallet, op2.nonce, submissionTokens2[2]
            )
        );
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op2, submissionTokens2[2], opDigests, v, r, s);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, aliceWallet, op2.nonce, submissionTokens1[2]
            )
        );
        aliceWallet.executeMultiQuarkOperationWithSubmissionToken(op1, submissionTokens1[2], opDigests, v, r, s);
    }

    /* ===== basic operation tests ===== */

    function testAtomicMaxCounterScript() public {
        // gas: disable metering except while executing operations
        vm.pauseGasMetering();

        bytes memory maxCounterScript = new YulHelper().getCode("MaxCounterScript.sol/MaxCounterScript.json");
        assertEq(counter.number(), 0);

        vm.startPrank(address(aliceAccount));

        (QuarkWallet.QuarkOperation memory op, bytes32[] memory submissionTokens) = new QuarkOperationHelper()
            .newReplayableOpWithCalldata(
            aliceWallet, maxCounterScript, abi.encodeCall(MaxCounterScript.run, (counter)), ScriptType.ScriptAddress, 4
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // call once
        vm.resumeGasMetering();
        vm.expectEmit(true, true, true, true);
        emit MaxCounterScript.Count(1);
        aliceWallet.executeQuarkOperation(op, v, r, s);

        // gas: do not meter walletStorage
        vm.pauseGasMetering();

        assertEq(counter.number(), 1);
        assertEq(
            vm.load(address(aliceWallet), keccak256(abi.encodePacked(op.nonce, keccak256("count")))),
            bytes32(uint256(1))
        );

        // call twice
        vm.resumeGasMetering();
        vm.expectEmit(true, true, true, true);
        emit MaxCounterScript.Count(2);
        aliceWallet.executeQuarkOperationWithSubmissionToken(op, submissionTokens[1], v, r, s);

        // gas: do not meter walletStorage
        vm.pauseGasMetering();

        assertEq(counter.number(), 2);
        assertEq(
            vm.load(address(aliceWallet), keccak256(abi.encodePacked(op.nonce, keccak256("count")))),
            bytes32(uint256(2))
        );

        // call thrice
        vm.resumeGasMetering();
        vm.expectEmit(true, true, true, true);
        emit MaxCounterScript.Count(3);
        aliceWallet.executeQuarkOperationWithSubmissionToken(op, submissionTokens[2], v, r, s);

        // gas: do not meter walletStorage
        vm.pauseGasMetering();

        assertEq(counter.number(), 3);
        assertEq(
            vm.load(address(aliceWallet), keccak256(abi.encodePacked(op.nonce, keccak256("count")))),
            bytes32(uint256(3))
        );

        // revert because max has been hit
        vm.expectRevert(abi.encodeWithSelector(MaxCounterScript.EnoughAlready.selector));
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperationWithSubmissionToken(op, submissionTokens[3], v, r, s);

        // gas: do not meter walletStorage
        vm.pauseGasMetering();

        assertEq(counter.number(), 3);
        assertEq(
            vm.load(address(aliceWallet), keccak256(abi.encodePacked(op.nonce, keccak256("count")))),
            bytes32(uint256(3))
        );

        counter.increment();
        assertEq(counter.number(), 4);
        assertEq(
            vm.load(address(aliceWallet), keccak256(abi.encodePacked(op.nonce, keccak256("count")))),
            bytes32(uint256(3))
        );

        vm.resumeGasMetering();
        vm.stopPrank();
    }

    function testQuarkOperationRevertsIfCallReverts() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory revertsCode = new YulHelper().getCode("Reverts.sol/Reverts.json");
        QuarkWallet.QuarkOperation memory op =
            new QuarkOperationHelper().newBasicOp(aliceWallet, revertsCode, ScriptType.ScriptSource);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert(abi.encodeWithSelector(Reverts.Whoops.selector));
        aliceWallet.executeQuarkOperation(op, v, r, s);
    }

    function testAtomicPing() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory ping = new YulHelper().getCode("Logger.sol/Logger.json");
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

    function testAtomicPingWithExternalSignature() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        assertEq(address(codeJar), address(0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f));

        /*
        Run `cat test/lib/Ping.yul0 | solc --bin --yul --evm-version paris -`
        */

        bytes32 nonce = bytes32(uint256(1));
        bytes memory pingCode =
            hex"6000356000527f48257dc961b6f792c2b78a080dacfed693b660960a702de21cee364e20270e2f60206000a1600080f3";
        bytes memory pingInitCode = new YulHelper().stub(pingCode);
        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = pingInitCode;
        address ping = codeJar.getCodeAddress(pingInitCode);
        address scriptAddress = ping;
        bytes memory scriptCalldata = hex"00000000000000000000000000000000000000000000000000000000000000dd";
        uint256 expiry = 9999999999999;

        // Note: these valueas are test so that if the test case changes any extrinsic values, we have
        //       a log of those values and can change the test accordingly.

        assertEq(aliceWallet.NAME(), "Quark Wallet");
        assertEq(aliceWallet.VERSION(), "1");
        assertEq(block.chainid, 31337);
        assertEq(address(aliceWallet), address(0xc7183455a4C133Ae270771860664b6B7ec320bB1));

        assertEq(nonce, bytes32(uint256(1))); // nonce
        assertEq(scriptAddress, address(0x4a925cF75dcc5708671004d9bbFAf4DCF2C762B0)); // scriptAddress
        assertEq(scriptSources.length, 1); // scriptSources
        assertEq(
            scriptSources[0],
            hex"630000003080600e6000396000f36000356000527f48257dc961b6f792c2b78a080dacfed693b660960a702de21cee364e20270e2f60206000a1600080f3"
        ); // scriptSources
        assertEq(scriptCalldata, hex"00000000000000000000000000000000000000000000000000000000000000dd");
        assertEq(expiry, 9999999999999);

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptAddress: scriptAddress,
            scriptSources: scriptSources,
            scriptCalldata: scriptCalldata,
            nonce: nonce,
            isReplayable: false,
            expiry: expiry
        });

        /*
        ethers.TypedDataEncoder.encode(
           {
               name: 'Quark Wallet',
               version: '1',
               chainId: 31337,
               verifyingContract: '0xc7183455a4C133Ae270771860664b6B7ec320bB1'
           },
           { QuarkOperation: [
               { name: 'nonce', type: 'bytes32' },
               { name: 'isReplayable', type: 'bool' },
               { name: 'scriptAddress', type: 'address' },
               { name: 'scriptSources', type: 'bytes[]' },
               { name: 'scriptCalldata', type: 'bytes' },
               { name: 'expiry', type: 'uint256' }
           ]},
           {
                nonce: '0x0000000000000000000000000000000000000000000000000000000000000001',
                isReplayable: false,
                scriptAddress: '0x4a925cF75dcc5708671004d9bbFAf4DCF2C762B0',
                scriptSources: ['0x630000003080600e6000396000f36000356000527f48257dc961b6f792c2b78a080dacfed693b660960a702de21cee364e20270e2f60206000a1600080f3'],
                scriptCalldata: '0x00000000000000000000000000000000000000000000000000000000000000dd',
                expiry: 9999999999999
           }
        )
        */

        bytes memory sigHash =
            hex"1901420cb4769bd47ac11897b8b69b8d80a84b9ec8b69437cd42529681d583a6b5218c7d870a6510d1840f2ec48a08d65eb874fa8af841e45e3c9b8e5c244bdc015f";
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, keccak256(sigHash));

        // gas: meter execute
        vm.resumeGasMetering();
        // TODO: Check who emitted.
        vm.expectEmit(true, true, true, true);
        emit Ping(0xdd);
        aliceWallet.executeQuarkOperation(op, v, r, s);
    }

    function testAtomicIncrementer() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");
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

    /* ===== execution on Precompiles ===== */
    // Quark is no longer able call precompiles directly due to empty code check, so these tests are commented out

    function testPrecompileEcRecover() public {
        vm.pauseGasMetering();
        bytes memory preCompileCaller = new YulHelper().getCode("PrecompileCaller.sol/PrecompileCaller.json");
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
    //         scriptSources: new bytes[](0),
    //         scriptCalldata: abi.encode(testHash, vt, rt, st),
    //         nonce: aliceWallet.nonceManager().nextNonce(address(aliceWallet)),
    //         expiry: block.timestamp + 1000
    //     });

    //     (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
    //     vm.resumeGasMetering();
    //     bytes memory rawOut = aliceWallet.executeQuarkOperation(op, v, r, s);
    //     assertEq(abi.decode(rawOut, (address)), aliceAccount);
    // }

    function testPrecompileSha256() public {
        vm.pauseGasMetering();
        bytes memory preCompileCaller = new YulHelper().getCode("PrecompileCaller.sol/PrecompileCaller.json");
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
    //         scriptSources: new bytes[](0),
    //         scriptCalldata: abi.encode(numberToHash),
    //         nonce: aliceWallet.nonceManager().nextNonce(address(aliceWallet)),
    //         expiry: block.timestamp + 1000
    //     });

    //     (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
    //     vm.resumeGasMetering();
    //     bytes memory output = aliceWallet.executeQuarkOperation(op, v, r, s);
    //     assertEq(abi.decode(output, (bytes32)), sha256(abi.encodePacked(numberToHash)));
    // }

    function testPrecompileRipemd160() public {
        vm.pauseGasMetering();
        bytes memory preCompileCaller = new YulHelper().getCode("PrecompileCaller.sol/PrecompileCaller.json");
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
    //         scriptSources: new bytes[](0),
    //         scriptCalldata: testBytes,
    //         nonce: aliceWallet.nonceManager().nextNonce(address(aliceWallet)),
    //         expiry: block.timestamp + 1000
    //     });
    //     (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
    //     vm.resumeGasMetering();
    //     bytes memory output = aliceWallet.executeQuarkOperation(op, v, r, s);
    //     assertEq(bytes20(abi.decode(output, (bytes32)) << 96), ripemd160(testBytes));
    // }

    function testPrecompileDataCopy() public {
        vm.pauseGasMetering();
        bytes memory preCompileCaller = new YulHelper().getCode("PrecompileCaller.sol/PrecompileCaller.json");
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
    //         scriptSources: new bytes[](0),
    //         scriptCalldata: testBytes,
    //         nonce: aliceWallet.nonceManager().nextNonce(address(aliceWallet)),
    //         expiry: block.timestamp + 1000
    //     });
    //     (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
    //     vm.resumeGasMetering();
    //     bytes memory output = aliceWallet.executeQuarkOperation(op, v, r, s);
    //     assertEq(output, testBytes);
    // }

    function testPrecompileBigModExp() public {
        vm.pauseGasMetering();
        bytes memory preCompileCaller = new YulHelper().getCode("PrecompileCaller.sol/PrecompileCaller.json");
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
    //         scriptSources: new bytes[](0),
    //         scriptCalldata: abi.encode(uint256(0x20), uint256(0x20), uint256(0x20), base, exponent, modulus),
    //         nonce: aliceWallet.nonceManager().nextNonce(address(aliceWallet)),
    //         expiry: block.timestamp + 1000
    //     });
    //     (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
    //     vm.resumeGasMetering();
    //     bytes memory output = aliceWallet.executeQuarkOperation(op, v, r, s);
    //     assertEq(abi.decode(output, (bytes32)), expected);
    // }

    function testPrecompileBn256Add() public {
        vm.pauseGasMetering();
        bytes memory preCompileCaller = new YulHelper().getCode("PrecompileCaller.sol/PrecompileCaller.json");
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
    //         scriptSources: new bytes[](0),
    //         scriptCalldata: abi.encode(input),
    //         nonce: aliceWallet.nonceManager().nextNonce(address(aliceWallet)),
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
        bytes memory preCompileCaller = new YulHelper().getCode("PrecompileCaller.sol/PrecompileCaller.json");
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
    //         scriptSources: new bytes[](0),
    //         scriptCalldata: abi.encode(input),
    //         nonce: aliceWallet.nonceManager().nextNonce(address(aliceWallet)),
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
        bytes memory preCompileCaller = new YulHelper().getCode("PrecompileCaller.sol/PrecompileCaller.json");
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
    //         scriptSources: new bytes[](0),
    //         scriptCalldata: abi.encodePacked(rounds, h[0], h[1], m[0], m[1], m[2], m[3], t[0], t[1], f),
    //         nonce: aliceWallet.nonceManager().nextNonce(address(aliceWallet)),
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
        bytes32 nonce = new QuarkOperationHelper().semiRandomNonce(nonceManager, aliceWallet);
        for (uint256 i = 1; i <= 9; i++) {
            vm.pauseGasMetering();
            nonce = new QuarkOperationHelper().incrementNonce(nonce);
            QuarkWallet.QuarkOperation memory op = DummyQuarkOperation(address(uint160(i)), nonce);
            (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
            vm.resumeGasMetering();
            vm.expectRevert(abi.encodeWithSelector(QuarkWallet.EmptyCode.selector));
            aliceWallet.executeQuarkOperation(op, v, r, s);
        }
    }

    function DummyQuarkOperation(address preCompileAddress, bytes32 nonce)
        internal
        view
        returns (QuarkWallet.QuarkOperation memory)
    {
        return QuarkWallet.QuarkOperation({
            scriptAddress: preCompileAddress,
            scriptSources: new bytes[](0),
            scriptCalldata: hex"",
            nonce: nonce,
            isReplayable: false,
            expiry: block.timestamp + 1000
        });
    }
}
