// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {BatchExecutor} from "quark-core/src/periphery/BatchExecutor.sol";
import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";
import {QuarkWallet, QuarkWalletStandalone} from "quark-core/src/QuarkWallet.sol";

import {Counter} from "test/lib/Counter.sol";
import {MaxCounterScript} from "test/lib/MaxCounterScript.sol";
import {Reverts} from "test/lib/Reverts.sol";

import {YulHelper} from "test/lib/YulHelper.sol";
import {SignatureHelper} from "test/lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "test/lib/QuarkOperationHelper.sol";

contract BatchExecutorTest is Test {
    event Ping(uint256);

    BatchExecutor public batchExecutor;
    CodeJar public codeJar;
    Counter public counter;
    QuarkStateManager public stateManager;

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

        stateManager = new QuarkStateManager();
        console.log("QuarkStateManager deployed to: %s", address(stateManager));

        aliceWallet = new QuarkWalletStandalone(aliceAccount, address(0), codeJar, stateManager);
        console.log("Alice wallet at: %s", address(aliceWallet));

        bobWallet = new QuarkWalletStandalone(bobAccount, address(0), codeJar, stateManager);
        console.log("Bob wallet at: %s", address(bobWallet));
    }

    function testBatchExecute() public {
        // FIXME: this comment below doesnt probably make sense
        // We test multiple operations with different wallets, covering both `scriptAddress` and `scriptSource` use-cases
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
        batchExecutor.batchExecuteOperations(ops);

        assertEq(counter.number(), 3);
    }

    function testBatchExecuteDoesNotRevertIfAnyCallsRevert() public {
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
        batchExecutor.batchExecuteOperations(ops);

        // Note: We removed returning success as a gas optimization, but these are the expected successes
        // assertEq(successes[0], true);
        // assertEq(successes[1], false);
        // // Should fail with OOG
        // assertEq(successes[2], false);
    }
}
