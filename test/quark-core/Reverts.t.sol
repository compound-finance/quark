// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "quark-core/src/CodeJar.sol";
import "quark-core/src/QuarkWallet.sol";
import "quark-core/src/QuarkStateManager.sol";

import "test/lib/Counter.sol";
import "test/lib/MaxCounterScript.sol";
import "test/lib/Reverts.sol";

import "test/lib/YulHelper.sol";
import "test/lib/SignatureHelper.sol";
import "test/lib/QuarkOperationHelper.sol";

contract RevertsTest is Test {
    CodeJar public codeJar;
    Counter public counter;
    QuarkStateManager public stateManager;

    uint256 alicePrivateKey = 0x8675309;
    address aliceAccount = vm.addr(alicePrivateKey);
    QuarkWallet aliceWallet; // see constructor()

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));

        stateManager = new QuarkStateManager();
        console.log("QuarkStateManager deployed to: %s", address(stateManager));

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
}
