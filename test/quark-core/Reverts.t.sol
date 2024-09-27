// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkNonceManager} from "quark-core/src/QuarkNonceManager.sol";
import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkWalletStandalone} from "quark-core/src/QuarkWalletStandalone.sol";

import {Counter} from "test/lib/Counter.sol";
import {Reverts} from "test/lib/Reverts.sol";

import {YulHelper} from "test/lib/YulHelper.sol";
import {SignatureHelper} from "test/lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "test/lib/QuarkOperationHelper.sol";

contract RevertsTest is Test {
    CodeJar public codeJar;
    Counter public counter;
    QuarkNonceManager public nonceManager;

    uint256 alicePrivateKey = 0x8675309;
    address aliceAccount = vm.addr(alicePrivateKey);
    QuarkWallet aliceWallet; // see constructor()

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));

        nonceManager = new QuarkNonceManager();
        console.log("QuarkNonceManager deployed to: %s", address(nonceManager));

        aliceWallet = new QuarkWalletStandalone(aliceAccount, address(0), codeJar, nonceManager);
        console.log("Alice signer: %s", aliceAccount);
        console.log("Alice wallet at: %s", address(aliceWallet));
    }

    /* ===== msg.value and msg.sender tests ===== */

    function testRevertsWhenDividingByZero() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory revertsCode = new YulHelper().getCode("Reverts.sol/Reverts.json");
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet, revertsCode, abi.encodeWithSelector(Reverts.divideByZero.selector), ScriptType.ScriptAddress
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        // Reverts with "panic: division or modulo by zero (0x12)"
        vm.expectRevert();
        aliceWallet.executeQuarkOperation(op, signature);
    }

    function testRevertsInteger() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory revertsCode = new YulHelper().getCode("Reverts.sol/Reverts.json");
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet, revertsCode, abi.encodeWithSelector(Reverts.revertSeven.selector), ScriptType.ScriptAddress
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        vm.expectRevert(hex"0000000000000000000000000000000000000000000000000000000000000007");
        aliceWallet.executeQuarkOperation(op, signature);
    }

    function testRevertsOutOfGas() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory revertsCode = new YulHelper().getCode("Reverts.sol/Reverts.json");
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet, revertsCode, abi.encodeWithSelector(Reverts.outOfGas.selector), ScriptType.ScriptAddress
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        // Reverts with "EvmError: OutOfGas"
        vm.expectRevert();
        aliceWallet.executeQuarkOperation{gas: 300_000}(op, signature);
    }

    function testRevertsInvalidOpcode() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory revertsCode = new YulHelper().getCode("Reverts.sol/Reverts.json");
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            revertsCode,
            abi.encodeWithSelector(Reverts.invalidOpcode.selector, codeJar),
            ScriptType.ScriptAddress
        );
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        // Reverts with "EvmError: InvalidFEOpcode"
        vm.expectRevert();
        aliceWallet.executeQuarkOperation(op, signature);
    }
}
