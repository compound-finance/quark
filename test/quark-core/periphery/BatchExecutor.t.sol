// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {BatchExecutor} from "quark-core/src/periphery/BatchExecutor.sol";
import {CodeJar} from "quark-core/src/CodeJar.sol";
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
        // We test multiple operations with different wallets, covering both `scriptAddress` and `scriptSource` use-cases
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory ping = new YulHelper().getDeployed("Logger.sol/Logger.json");
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");

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
        address[] memory accounts = new address[](2);
        QuarkWallet.QuarkOperation[] memory operations = new QuarkWallet.QuarkOperation[](2);
        uint8[] memory v = new uint8[](2);
        bytes32[] memory r = new bytes32[](2);
        bytes32[] memory s = new bytes32[](2);
        accounts[0] = address(aliceWallet);
        accounts[1] = address(bobWallet);
        operations[0] = aliceOp;
        operations[1] = bobOp;
        v[0] = v0;
        v[1] = v1;
        r[0] = r0;
        r[1] = r1;
        s[0] = s0;
        s[1] = s1;

        assertEq(counter.number(), 0);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectEmit(false, false, false, true);
        emit Ping(55);
        batchExecutor.batchExecuteOperations(accounts, operations, v, r, s);

        assertEq(counter.number(), 3);
    }

    function testBatchExecuteRevertsIfAnyCallReverts() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory ping = new YulHelper().getDeployed("Logger.sol/Logger.json");
        bytes memory reverts = new YulHelper().getDeployed("Reverts.sol/Reverts.json");

        QuarkWallet.QuarkOperation memory aliceOp =
            new QuarkOperationHelper().newBasicOp(aliceWallet, ping, ScriptType.ScriptAddress);
        (uint8 v0, bytes32 r0, bytes32 s0) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, aliceOp);
        QuarkWallet.QuarkOperation memory bobOp =
            new QuarkOperationHelper().newBasicOp(bobWallet, reverts, ScriptType.ScriptSource);
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(bobPrivateKey, bobWallet, bobOp);

        // Construct list of operations and signatures
        address[] memory accounts = new address[](2);
        QuarkWallet.QuarkOperation[] memory operations = new QuarkWallet.QuarkOperation[](2);
        uint8[] memory v = new uint8[](2);
        bytes32[] memory r = new bytes32[](2);
        bytes32[] memory s = new bytes32[](2);
        accounts[0] = address(aliceWallet);
        accounts[1] = address(bobWallet);
        operations[0] = aliceOp;
        operations[1] = bobOp;
        v[0] = v0;
        v[1] = v1;
        r[0] = r0;
        r[1] = r1;
        s[0] = s0;
        s[1] = s1;

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert(abi.encodeWithSelector(Reverts.Whoops.selector));
        batchExecutor.batchExecuteOperations(accounts, operations, v, r, s);
    }

    function testBatchExecuteRevertsOnBadInput() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        address[] memory accounts = new address[](2);
        QuarkWallet.QuarkOperation[] memory operations = new QuarkWallet.QuarkOperation[](2);
        uint8[] memory v = new uint8[](2);
        bytes32[] memory r = new bytes32[](2);
        bytes32[] memory s = new bytes32[](2);

        address[] memory invalidAccounts = new address[](3);
        QuarkWallet.QuarkOperation[] memory invalidOperations = new QuarkWallet.QuarkOperation[](1);
        uint8[] memory invalidV = new uint8[](0);
        bytes32[] memory invalidR = new bytes32[](5);
        bytes32[] memory invalidS = new bytes32[](10);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert(abi.encodeWithSelector(BatchExecutor.BadData.selector));
        batchExecutor.batchExecuteOperations(invalidAccounts, operations, v, r, s);

        vm.expectRevert(abi.encodeWithSelector(BatchExecutor.BadData.selector));
        batchExecutor.batchExecuteOperations(accounts, invalidOperations, v, r, s);

        vm.expectRevert(abi.encodeWithSelector(BatchExecutor.BadData.selector));
        batchExecutor.batchExecuteOperations(accounts, operations, invalidV, r, s);

        vm.expectRevert(abi.encodeWithSelector(BatchExecutor.BadData.selector));
        batchExecutor.batchExecuteOperations(accounts, operations, v, invalidR, s);

        vm.expectRevert(abi.encodeWithSelector(BatchExecutor.BadData.selector));
        batchExecutor.batchExecuteOperations(accounts, operations, v, r, invalidS);
    }
}
