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

import {Counter} from "test/lib/Counter.sol";
import {MaxCounterScript} from "test/lib/MaxCounterScript.sol";
import {Stow} from "test/lib/Noncer.sol";

contract NoncerTest is Test {
    enum ExecutionType {
        Signature,
        Direct
    }

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

    /**
     * get active nonce, submission token, replay count ***************************
     *
     * single
     */
    function testGetActiveNonceSingle() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory noncerScript = new YulHelper().getCode("Noncer.sol/Noncer.json");
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet, noncerScript, abi.encodeWithSignature("checkNonce()"), ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWallet.executeQuarkOperation(op, signature);

        (bytes32 nonceResult) = abi.decode(result, (bytes32));
        assertEq(nonceResult, op.nonce);
    }

    function testGetActiveSubmissionTokenSingle() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory noncerScript = new YulHelper().getCode("Noncer.sol/Noncer.json");
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet, noncerScript, abi.encodeWithSignature("checkSubmissionToken()"), ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWallet.executeQuarkOperation(op, signature);

        (bytes32 submissionTokenResult) = abi.decode(result, (bytes32));
        assertEq(submissionTokenResult, op.nonce);
        assertEq(nonceManager.submissions(address(aliceWallet), op.nonce), bytes32(type(uint256).max));
    }

    function testGetActiveReplayCountSingle() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory noncerScript = new YulHelper().getCode("Noncer.sol/Noncer.json");
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet, noncerScript, abi.encodeWithSignature("checkReplayCount()"), ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWallet.executeQuarkOperation(op, signature);

        (uint256 replayCount) = abi.decode(result, (uint256));
        assertEq(replayCount, 0);
    }

    /*
     * nested
     */

    function testGetActiveNonceNested() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory noncerScript = new YulHelper().getCode("Noncer.sol/Noncer.json");
        QuarkWallet.QuarkOperation memory nestedOp = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet, noncerScript, abi.encodeWithSignature("checkNonce()"), ScriptType.ScriptSource
        );
        nestedOp.nonce = bytes32(uint256(keccak256(abi.encodePacked(block.timestamp))) - 2); // Don't overlap on nonces
        bytes memory nestedOpSignature = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, nestedOp);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            noncerScript,
            abi.encodeWithSignature(
                "nestedNonce((bytes32,bool,address,bytes[],bytes,uint256),bytes)", nestedOp, nestedOpSignature
            ),
            ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWallet.executeQuarkOperation(op, signature);

        (bytes32 pre, bytes32 post, bytes memory innerResult) = abi.decode(result, (bytes32, bytes32, bytes));
        assertEq(pre, op.nonce);
        assertEq(post, op.nonce);
        bytes32 innerNonce = abi.decode(innerResult, (bytes32));
        assertEq(innerNonce, nestedOp.nonce);
    }

    function testGetActiveSubmissionTokenNested() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory noncerScript = new YulHelper().getCode("Noncer.sol/Noncer.json");
        QuarkWallet.QuarkOperation memory nestedOp = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet, noncerScript, abi.encodeWithSignature("checkSubmissionToken()"), ScriptType.ScriptSource
        );
        nestedOp.nonce = bytes32(uint256(keccak256(abi.encodePacked(block.timestamp))) - 2); // Don't overlap on nonces
        bytes memory nestedOpSignature = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, nestedOp);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            noncerScript,
            abi.encodeWithSignature(
                "nestedSubmissionToken((bytes32,bool,address,bytes[],bytes,uint256),bytes)", nestedOp, nestedOpSignature
            ),
            ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWallet.executeQuarkOperation(op, signature);

        (bytes32 pre, bytes32 post, bytes memory innerResult) = abi.decode(result, (bytes32, bytes32, bytes));
        assertEq(pre, op.nonce);
        assertEq(post, op.nonce);
        bytes32 innerNonce = abi.decode(innerResult, (bytes32));
        assertEq(innerNonce, nestedOp.nonce);
    }

    // Complicated test for a nested script to call itself recursive, since it's fun to test wonky cases.
    function testNestedPlayPullingActiveReplayCount() public {
        Stow stow = new Stow();

        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory noncerScript = new YulHelper().getCode("Noncer.sol/Noncer.json");
        (QuarkWallet.QuarkOperation memory op, bytes32[] memory submissionTokens) = new QuarkOperationHelper()
            .newReplayableOpWithCalldata(
            aliceWallet, noncerScript, abi.encodeWithSignature("nestedPlay(address)", stow), ScriptType.ScriptSource, 1
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        stow.setNestedOperation(op, submissionTokens[1], signature);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWallet.executeQuarkOperation(op, signature);

        (uint256 y) = abi.decode(result, (uint256));
        assertEq(y, 61);
    }

    function testGetActiveReplayCountNested() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory noncerScript = new YulHelper().getCode("Noncer.sol/Noncer.json");
        QuarkWallet.QuarkOperation memory nestedOp = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet, noncerScript, abi.encodeWithSignature("checkReplayCount()"), ScriptType.ScriptSource
        );
        nestedOp.nonce = bytes32(uint256(keccak256(abi.encodePacked(block.timestamp))) - 2); // Don't overlap on nonces
        bytes memory nestedOpSignature = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, nestedOp);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            noncerScript,
            abi.encodeWithSignature(
                "nestedReplayCount((bytes32,bool,address,bytes[],bytes,uint256),bytes)", nestedOp, nestedOpSignature
            ),
            ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWallet.executeQuarkOperation(op, signature);

        (uint256 pre, uint256 post, bytes memory innerResult) = abi.decode(result, (uint256, uint256, bytes));
        assertEq(pre, 0);
        assertEq(post, 0);
        uint256 innerNonce = abi.decode(innerResult, (uint256));
        assertEq(innerNonce, 0);
    }

    function testPostNestReadsCorrectValue() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory noncerScript = new YulHelper().getCode("Noncer.sol/Noncer.json");
        bytes memory maxCounter = new YulHelper().getCode("MaxCounterScript.sol/MaxCounterScript.json");
        QuarkWallet.QuarkOperation memory nestedOp = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet, maxCounter, abi.encodeWithSignature("run(address)", address(counter)), ScriptType.ScriptSource
        );
        nestedOp.nonce = bytes32(uint256(keccak256(abi.encodePacked(block.timestamp))) - 2); // Don't overlap on nonces
        bytes memory nestedOpSignature = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, nestedOp);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            noncerScript,
            abi.encodeWithSignature(
                "postNestRead((bytes32,bool,address,bytes[],bytes,uint256),bytes)", nestedOp, nestedOpSignature
            ),
            ScriptType.ScriptSource
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWallet.executeQuarkOperation(op, signature);

        uint256 value = abi.decode(result, (uint256));
        assertEq(value, 0);
        // Counter should be incremented in storage for the inner op, not the outer op
        assertEq(
            vm.load(address(aliceWallet), keccak256(abi.encodePacked(op.nonce, keccak256("count")))),
            bytes32(uint256(0))
        );
        assertEq(
            vm.load(address(aliceWallet), keccak256(abi.encodePacked(nestedOp.nonce, keccak256("count")))),
            bytes32(uint256(1))
        );
    }

    /*
     * replayable
     */

    function testGetActiveNonceReplayable() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory noncerScript = new YulHelper().getCode("Noncer.sol/Noncer.json");
        (QuarkWallet.QuarkOperation memory op, bytes32[] memory submissionTokens) = new QuarkOperationHelper()
            .newReplayableOpWithCalldata(
            aliceWallet, noncerScript, abi.encodeWithSignature("checkNonce()"), ScriptType.ScriptSource, 1
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWallet.executeQuarkOperation(op, signature);

        (bytes32 nonceResult) = abi.decode(result, (bytes32));
        assertEq(nonceResult, op.nonce);

        result = aliceWallet.executeQuarkOperationWithSubmissionToken(op, submissionTokens[1], signature);

        (nonceResult) = abi.decode(result, (bytes32));
        assertEq(nonceResult, op.nonce);
    }

    function testGetActiveSubmissionTokenReplayable() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory noncerScript = new YulHelper().getCode("Noncer.sol/Noncer.json");
        (QuarkWallet.QuarkOperation memory op, bytes32[] memory submissionTokens) = new QuarkOperationHelper()
            .newReplayableOpWithCalldata(
            aliceWallet, noncerScript, abi.encodeWithSignature("checkSubmissionToken()"), ScriptType.ScriptSource, 1
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWallet.executeQuarkOperation(op, signature);

        (bytes32 submissionTokenResult) = abi.decode(result, (bytes32));
        assertEq(submissionTokenResult, submissionTokens[0]);

        result = aliceWallet.executeQuarkOperationWithSubmissionToken(op, submissionTokens[1], signature);

        (submissionTokenResult) = abi.decode(result, (bytes32));
        assertEq(submissionTokenResult, submissionTokens[1]);
    }

    function testGetActiveReplayCount() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory noncerScript = new YulHelper().getCode("Noncer.sol/Noncer.json");
        (QuarkWallet.QuarkOperation memory op, bytes32[] memory submissionTokens) = new QuarkOperationHelper()
            .newReplayableOpWithCalldata(
            aliceWallet, noncerScript, abi.encodeWithSignature("checkReplayCount()"), ScriptType.ScriptSource, 2
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWallet.executeQuarkOperation(op, signature);

        (uint256 replayCount) = abi.decode(result, (uint256));
        assertEq(replayCount, 0);

        result = aliceWallet.executeQuarkOperationWithSubmissionToken(op, submissionTokens[1], signature);

        (replayCount) = abi.decode(result, (uint256));
        assertEq(replayCount, 1);

        result = aliceWallet.executeQuarkOperationWithSubmissionToken(op, submissionTokens[2], signature);

        (replayCount) = abi.decode(result, (uint256));
        assertEq(replayCount, 2);
    }

    function testGetActiveReplayCountWithNonReplaySoftCancel() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory noncerScript = new YulHelper().getCode("Noncer.sol/Noncer.json");
        bytes memory checkNonceScript = new YulHelper().getCode("CheckNonceScript.sol/CheckNonceScript.json");
        (QuarkWallet.QuarkOperation memory op, bytes32[] memory submissionTokens) = new QuarkOperationHelper()
            .newReplayableOpWithCalldata(
            aliceWallet, noncerScript, abi.encodeWithSignature("checkReplayCount()"), ScriptType.ScriptSource, 2
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        QuarkWallet.QuarkOperation memory checkReplayCountOp = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            checkNonceScript,
            abi.encodeWithSignature("checkReplayCount()"),
            ScriptType.ScriptSource,
            op.nonce
        );
        bytes memory checkReplayCountSignature =
            new SignatureHelper().signOp(alicePrivateKey, aliceWallet, checkReplayCountOp);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWallet.executeQuarkOperation(op, signature);

        (uint256 replayCount) = abi.decode(result, (uint256));
        assertEq(replayCount, 0);

        result = aliceWallet.executeQuarkOperationWithSubmissionToken(
            checkReplayCountOp, submissionTokens[1], checkReplayCountSignature
        );

        (replayCount) = abi.decode(result, (uint256));
        assertEq(replayCount, 1);

        assertEq(nonceManager.submissions(address(aliceWallet), op.nonce), bytes32(type(uint256).max));
    }
}
