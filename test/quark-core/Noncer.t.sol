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

import {Stow} from "test/lib/Noncer.sol";

contract NoncerTest is Test {
    enum ExecutionType {
        Signature,
        Direct
    }

    CodeJar public codeJar;
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
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWallet.executeQuarkOperation(op, v, r, s);

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
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWallet.executeQuarkOperation(op, v, r, s);

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
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWallet.executeQuarkOperation(op, v, r, s);

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
        (uint8 nestedV, bytes32 nestedR, bytes32 nestedS) =
            new SignatureHelper().signOp(alicePrivateKey, aliceWallet, nestedOp);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            noncerScript,
            abi.encodeWithSignature(
                "nestedNonce((bytes32,bool,address,bytes[],bytes,uint256),uint8,bytes32,bytes32)",
                nestedOp,
                nestedV,
                nestedR,
                nestedS
            ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWallet.executeQuarkOperation(op, v, r, s);

        (bytes32 pre, bytes32 post, bytes memory innerResult) = abi.decode(result, (bytes32, bytes32, bytes));
        assertEq(pre, op.nonce);
        assertEq(post, bytes32(0));
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
        (uint8 nestedV, bytes32 nestedR, bytes32 nestedS) =
            new SignatureHelper().signOp(alicePrivateKey, aliceWallet, nestedOp);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            noncerScript,
            abi.encodeWithSignature(
                "nestedSubmissionToken((bytes32,bool,address,bytes[],bytes,uint256),uint8,bytes32,bytes32)",
                nestedOp,
                nestedV,
                nestedR,
                nestedS
            ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWallet.executeQuarkOperation(op, v, r, s);

        (bytes32 pre, bytes32 post, bytes memory innerResult) = abi.decode(result, (bytes32, bytes32, bytes));
        assertEq(pre, op.nonce);
        assertEq(post, bytes32(0));
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
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        stow.setNestedOperation(op, submissionTokens[1], v, r, s);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWallet.executeQuarkOperation(op, v, r, s);

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
        (uint8 nestedV, bytes32 nestedR, bytes32 nestedS) =
            new SignatureHelper().signOp(alicePrivateKey, aliceWallet, nestedOp);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            noncerScript,
            abi.encodeWithSignature(
                "nestedReplayCount((bytes32,bool,address,bytes[],bytes,uint256),uint8,bytes32,bytes32)",
                nestedOp,
                nestedV,
                nestedR,
                nestedS
            ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWallet.executeQuarkOperation(op, v, r, s);

        (uint256 pre, uint256 post, bytes memory innerResult) = abi.decode(result, (uint256, uint256, bytes));
        assertEq(pre, 0);
        assertEq(post, 0);
        uint256 innerNonce = abi.decode(innerResult, (uint256));
        assertEq(innerNonce, 0);
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
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWallet.executeQuarkOperation(op, v, r, s);

        (bytes32 nonceResult) = abi.decode(result, (bytes32));
        assertEq(nonceResult, op.nonce);

        result = aliceWallet.executeQuarkOperationWithSubmissionToken(op, submissionTokens[1], v, r, s);

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
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWallet.executeQuarkOperation(op, v, r, s);

        (bytes32 submissionTokenResult) = abi.decode(result, (bytes32));
        assertEq(submissionTokenResult, submissionTokens[0]);

        result = aliceWallet.executeQuarkOperationWithSubmissionToken(op, submissionTokens[1], v, r, s);

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
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWallet.executeQuarkOperation(op, v, r, s);

        (uint256 replayCount) = abi.decode(result, (uint256));
        assertEq(replayCount, 0);

        result = aliceWallet.executeQuarkOperationWithSubmissionToken(op, submissionTokens[1], v, r, s);

        (replayCount) = abi.decode(result, (uint256));
        assertEq(replayCount, 1);

        result = aliceWallet.executeQuarkOperationWithSubmissionToken(op, submissionTokens[2], v, r, s);

        (replayCount) = abi.decode(result, (uint256));
        assertEq(replayCount, 2);
    }

    function testGetActiveReplayCountWithCancel() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory noncerScript = new YulHelper().getCode("Noncer.sol/Noncer.json");
        (QuarkWallet.QuarkOperation memory op, bytes32[] memory submissionTokens) = new QuarkOperationHelper()
            .newReplayableOpWithCalldata(
            aliceWallet, noncerScript, abi.encodeWithSignature("checkReplayCount()"), ScriptType.ScriptSource, 2
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        QuarkWallet.QuarkOperation memory cancelOp =
            new QuarkOperationHelper().cancelReplayable(aliceWallet, op, abi.encodeWithSignature("checkReplayCount()"));
        (uint8 cancelV, bytes32 cancelR, bytes32 cancelS) =
            new SignatureHelper().signOp(alicePrivateKey, aliceWallet, cancelOp);

        // gas: meter execute
        vm.resumeGasMetering();
        bytes memory result = aliceWallet.executeQuarkOperation(op, v, r, s);

        (uint256 replayCount) = abi.decode(result, (uint256));
        assertEq(replayCount, 0);

        result = aliceWallet.executeQuarkOperationWithSubmissionToken(
            cancelOp, submissionTokens[1], cancelV, cancelR, cancelS
        );

        (replayCount) = abi.decode(result, (uint256));
        assertEq(replayCount, 1);

        assertEq(nonceManager.submissions(address(aliceWallet), op.nonce), bytes32(type(uint256).max));
    }
}