// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {BatchExecutor} from "quark-core/src/periphery/BatchExecutor.sol";
import {QuarkNonceManager} from "quark-core/src/QuarkNonceManager.sol";
import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";

import {QuarkMinimalProxy} from "quark-proxy/src/QuarkMinimalProxy.sol";

import {Counter} from "test/lib/Counter.sol";
import {Reverts} from "test/lib/Reverts.sol";

import {YulHelper} from "test/lib/YulHelper.sol";
import {SignatureHelper} from "test/lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "test/lib/QuarkOperationHelper.sol";

contract BatchExecutorTest is Test {
    event Ping(uint256);

    BatchExecutor public batchExecutor;
    CodeJar public codeJar;
    Counter public counter;
    QuarkNonceManager public nonceManager;
    QuarkWallet public walletImplementation;

    uint256 alicePrivateKey = 0x8675309;
    uint256 bobPrivateKey = 0xb0b5309;
    address aliceAccount = vm.addr(alicePrivateKey);
    address bobAccount = vm.addr(bobPrivateKey);
    QuarkWallet aliceWallet; // see constructor()
    QuarkWallet bobWallet; // see constructor()

    constructor() {
        batchExecutor = new BatchExecutor();
        console.log("BatchExecutor deployed to: %s", address(batchExecutor));

        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));

        nonceManager = new QuarkNonceManager();
        console.log("QuarkNonceManager deployed to: %s", address(nonceManager));

        walletImplementation = new QuarkWallet(codeJar, nonceManager);
        console.log("QuarkWallet implementation: %s", address(walletImplementation));

        aliceWallet =
            QuarkWallet(payable(new QuarkMinimalProxy(address(walletImplementation), aliceAccount, address(0))));
        console.log("Alice wallet at: %s", address(aliceWallet));

        bobWallet = QuarkWallet(payable(new QuarkMinimalProxy(address(walletImplementation), bobAccount, address(0))));
        console.log("Bob wallet at: %s", address(aliceWallet));
    }

    function testBatchExecuteWithPartialFailures() public {
        // We test multiple operations with different wallets
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory ping = new YulHelper().getCode("Logger.sol/Logger.json");
        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");

        QuarkWallet.QuarkOperation memory aliceOp =
            new QuarkOperationHelper().newBasicOp(aliceWallet, ping, ScriptType.ScriptAddress);
        (uint8 v0, bytes32 r0, bytes32 s0) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, aliceOp);
        QuarkWallet.QuarkOperation memory bobOp = new QuarkOperationHelper().newBasicOpWithCalldata(
            bobWallet,
            incrementer,
            abi.encodeWithSignature("incrementCounter(address)", counter),
            ScriptType.ScriptSource
        );
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(bobPrivateKey, bobWallet, bobOp);

        // Construct list of operations and signatures
        BatchExecutor.OperationParams[] memory ops = new BatchExecutor.OperationParams[](2);
        ops[0] = BatchExecutor.OperationParams({
            account: address(aliceWallet),
            op: aliceOp,
            v: v0,
            r: r0,
            s: s0,
            gasLimit: 0.1 ether
        });
        ops[1] = BatchExecutor.OperationParams({
            account: address(bobWallet),
            op: bobOp,
            v: v1,
            r: r1,
            s: s1,
            gasLimit: 0.1 ether
        });

        assertEq(counter.number(), 0);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectEmit(false, false, false, true);
        emit Ping(55);
        batchExecutor.batchExecuteOperations(ops, true);

        assertEq(counter.number(), 3);
    }

    function testBatchExecuteWithPartialFailuresDoesNotRevertIfAnyCallsRevert() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory ping = new YulHelper().getCode("Logger.sol/Logger.json");
        bytes memory reverts = new YulHelper().getCode("Reverts.sol/Reverts.json");

        QuarkWallet.QuarkOperation memory aliceOp =
            new QuarkOperationHelper().newBasicOp(aliceWallet, ping, ScriptType.ScriptAddress);
        (uint8 v0, bytes32 r0, bytes32 s0) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, aliceOp);
        QuarkWallet.QuarkOperation memory bobOp =
            new QuarkOperationHelper().newBasicOp(bobWallet, reverts, ScriptType.ScriptSource);
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(bobPrivateKey, bobWallet, bobOp);
        QuarkWallet.QuarkOperation memory aliceOp2 =
            new QuarkOperationHelper().newBasicOp(aliceWallet, ping, ScriptType.ScriptAddress);
        (uint8 v2, bytes32 r2, bytes32 s2) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, aliceOp2);

        // Construct list of operations and signatures
        BatchExecutor.OperationParams[] memory ops = new BatchExecutor.OperationParams[](3);
        ops[0] = BatchExecutor.OperationParams({
            account: address(aliceWallet),
            op: aliceOp,
            v: v0,
            r: r0,
            s: s0,
            gasLimit: 0.1 ether
        });
        ops[1] = BatchExecutor.OperationParams({
            account: address(bobWallet),
            op: bobOp,
            v: v1,
            r: r1,
            s: s1,
            gasLimit: 0.1 ether
        });
        ops[2] = BatchExecutor.OperationParams({
            account: address(aliceWallet),
            op: aliceOp2,
            v: v2,
            r: r2,
            s: s2,
            gasLimit: 1 wei // To trigger OOG
        });

        // gas: meter execute
        vm.resumeGasMetering();
        batchExecutor.batchExecuteOperations(ops, true);

        // Note: We removed returning success as a gas optimization, but these are the expected successes
        // assertEq(successes[0], true);
        // assertEq(successes[1], false);
        // // Should fail with OOG
        // assertEq(successes[2], false);
    }

    function testBatchExecuteWithoutPartialFailures() public {
        // We test multiple operations with different wallets
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory ping = new YulHelper().getCode("Logger.sol/Logger.json");
        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");

        QuarkWallet.QuarkOperation memory aliceOp =
            new QuarkOperationHelper().newBasicOp(aliceWallet, ping, ScriptType.ScriptAddress);
        (uint8 v0, bytes32 r0, bytes32 s0) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, aliceOp);
        QuarkWallet.QuarkOperation memory bobOp = new QuarkOperationHelper().newBasicOpWithCalldata(
            bobWallet,
            incrementer,
            abi.encodeWithSignature("incrementCounter(address)", counter),
            ScriptType.ScriptSource
        );
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(bobPrivateKey, bobWallet, bobOp);

        // Construct list of operations and signatures
        BatchExecutor.OperationParams[] memory ops = new BatchExecutor.OperationParams[](2);
        ops[0] = BatchExecutor.OperationParams({
            account: address(aliceWallet),
            op: aliceOp,
            v: v0,
            r: r0,
            s: s0,
            gasLimit: 0.1 ether
        });
        ops[1] = BatchExecutor.OperationParams({
            account: address(bobWallet),
            op: bobOp,
            v: v1,
            r: r1,
            s: s1,
            gasLimit: 0.1 ether
        });

        assertEq(counter.number(), 0);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectEmit(false, false, false, true);
        emit Ping(55);
        batchExecutor.batchExecuteOperations(ops, false);

        assertEq(counter.number(), 3);
    }

    function testBatchExecuteWithoutPartialFailuresRevertsIfAnyCallsRevert() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory ping = new YulHelper().getCode("Logger.sol/Logger.json");
        bytes memory reverts = new YulHelper().getCode("Reverts.sol/Reverts.json");

        QuarkWallet.QuarkOperation memory aliceOp =
            new QuarkOperationHelper().newBasicOp(aliceWallet, ping, ScriptType.ScriptAddress);
        (uint8 v0, bytes32 r0, bytes32 s0) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, aliceOp);
        QuarkWallet.QuarkOperation memory bobOp =
            new QuarkOperationHelper().newBasicOp(bobWallet, reverts, ScriptType.ScriptSource);
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(bobPrivateKey, bobWallet, bobOp);
        QuarkWallet.QuarkOperation memory aliceOp2 =
            new QuarkOperationHelper().newBasicOp(aliceWallet, ping, ScriptType.ScriptAddress);
        (uint8 v2, bytes32 r2, bytes32 s2) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, aliceOp2);

        // Construct list of operations and signatures
        BatchExecutor.OperationParams[] memory ops = new BatchExecutor.OperationParams[](3);
        ops[0] = BatchExecutor.OperationParams({
            account: address(aliceWallet),
            op: aliceOp,
            v: v0,
            r: r0,
            s: s0,
            gasLimit: 0.1 ether
        });
        ops[1] = BatchExecutor.OperationParams({
            account: address(bobWallet),
            op: bobOp,
            v: v1,
            r: r1,
            s: s1,
            gasLimit: 0.1 ether
        });
        ops[2] = BatchExecutor.OperationParams({
            account: address(aliceWallet),
            op: aliceOp2,
            v: v2,
            r: r2,
            s: s2,
            gasLimit: 1 wei // To trigger OOG
        });

        vm.expectRevert(
            abi.encodeWithSelector(BatchExecutor.BatchExecutionError.selector, 1, abi.encodeWithSignature("Whoops()"))
        );
        // gas: meter execute
        vm.resumeGasMetering();
        batchExecutor.batchExecuteOperations(ops, false);

        // Note: We removed returning success as a gas optimization, but these are the expected successes
        // assertEq(successes[0], true);
        // assertEq(successes[1], false);
        // // Should fail with OOG
        // assertEq(successes[2], false);
    }

    // TODO: Batch execution with submission tokens?
}
