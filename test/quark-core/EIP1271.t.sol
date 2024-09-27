// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/console.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkNonceManager} from "quark-core/src/QuarkNonceManager.sol";
import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkWalletStandalone} from "quark-core/src/QuarkWalletStandalone.sol";

import {Counter} from "test/lib/Counter.sol";
import {EIP1271Signer} from "test/lib/EIP1271Signer.sol";

import {YulHelper} from "test/lib/YulHelper.sol";
import {SignatureHelper} from "test/lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "test/lib/QuarkOperationHelper.sol";

contract EIP1271Test is Test {
    CodeJar public codeJar;
    Counter public counter;
    QuarkNonceManager public nonceManager;
    QuarkWallet public aliceWallet;

    uint256 alicePrivateKey = 0xa11ce;
    address alice; // see setup()

    function setUp() public {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));

        nonceManager = new QuarkNonceManager();
        console.log("QuarkNonceManager deployed to: %s", address(nonceManager));

        alice = vm.addr(alicePrivateKey);
        aliceWallet = new QuarkWalletStandalone(alice, address(0), codeJar, nonceManager);
    }

    function incrementCounterOperation(QuarkWallet targetWallet) public returns (QuarkWallet.QuarkOperation memory) {
        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");

        return new QuarkOperationHelper().newBasicOpWithCalldata(
            targetWallet,
            incrementer,
            abi.encodeWithSignature("incrementCounter(address)", counter),
            ScriptType.ScriptSource
        );
    }

    function testReturnsMagicValueForValidSignature() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        // QuarkWallet is owned by a smart contract that always approves signatures
        EIP1271Signer signatureApprover = new EIP1271Signer(true);
        QuarkWallet contractWallet =
            new QuarkWalletStandalone(address(signatureApprover), address(0), codeJar, nonceManager);

        // signature from alice; doesn't matter because the EIP1271Signer will approve anything
        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(aliceWallet);
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();

        contractWallet.executeQuarkOperation(op, signature);
        // counter has incremented
        assertEq(counter.number(), 3);
    }

    function testRevertsIfSignerContractDoesNotReturnMagic() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        // QuarkWallet is owned by a smart contract that always rejects signatures
        EIP1271Signer signatureApprover = new EIP1271Signer(false);
        QuarkWallet contractWallet =
            new QuarkWalletStandalone(address(signatureApprover), address(0), codeJar, nonceManager);

        // signature from alice; doesn't matter because the EIP1271Signer will reject anything
        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(aliceWallet);
        bytes memory signature = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();

        vm.expectRevert(QuarkWallet.InvalidEIP1271Signature.selector);
        contractWallet.executeQuarkOperation(op, signature);

        // counter has not incremented
        assertEq(counter.number(), 0);
    }
}
