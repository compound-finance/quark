// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

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

contract RevertsTest is Test {
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

    /* ===== msg.value and msg.sender tests ===== */

    function testRevertsWhenDividingByZero() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory revertsCode = new YulHelper().getDeployed("Reverts.sol/Reverts.json");
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet, revertsCode, abi.encodeWithSelector(Reverts.divideByZero.selector), ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        // Reverts with "panic: division or modulo by zero (0x12)"
        vm.expectRevert();
        aliceWallet.executeQuarkOperation(op, v, r, s);
    }

    function testRevertsInteger() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory revertsCode = new YulHelper().getDeployed("Reverts.sol/Reverts.json");
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet, revertsCode, abi.encodeWithSelector(Reverts.revertSeven.selector), ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert(hex"0000000000000000000000000000000000000000000000000000000000000007");
        aliceWallet.executeQuarkOperation(op, v, r, s);
    }

    function testRevertsOutOfGas() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory revertsCode = new YulHelper().getDeployed("Reverts.sol/Reverts.json");
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet, revertsCode, abi.encodeWithSelector(Reverts.outOfGas.selector), ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        // Reverts with "EvmError: OutOfGas"
        vm.expectRevert();
        aliceWallet.executeQuarkOperation{gas: 300_000}(op, v, r, s);
    }

    function testRevertsInvalidOpcode() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory revertsCode = new YulHelper().getDeployed("Reverts.sol/Reverts.json");
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            revertsCode,
            abi.encodeWithSelector(Reverts.invalidOpcode.selector, codeJar),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        // Reverts with "EvmError: InvalidFEOpcode"
        vm.expectRevert();
        aliceWallet.executeQuarkOperation(op, v, r, s);
    }

    function testRevertsOutOfMemory() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory revertsCode = new YulHelper().getDeployed("Reverts.sol/Reverts.json");
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet, revertsCode, abi.encodeWithSelector(Reverts.outOfMemory.selector), ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        // Reverts with "EvmError: MemoryLimitOOG"
        vm.expectRevert();
        aliceWallet.executeQuarkOperation(op, v, r, s);
    }
}
