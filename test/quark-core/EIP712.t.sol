// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/console.sol";

import {Test} from "forge-std/Test.sol";

import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {CodeJar} from "quark-core/src/CodeJar.sol";
import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";

import {Counter} from "test/lib/Counter.sol";
import {YulHelper} from "test/lib/YulHelper.sol";
import {SignatureHelper} from "test/lib/SignatureHelper.sol";
import {ExecuteWithRequirements} from "test/lib/ExecuteWithRequirements.sol";
import {QuarkOperationHelper, ScriptType} from "test/lib/QuarkOperationHelper.sol";

contract EIP712Test is Test {
    CodeJar public codeJar;
    Counter public counter;
    QuarkWallet public wallet;
    QuarkStateManager public stateManager;

    uint256 alicePrivateKey = 0xa11ce;
    address alice; // see setup()
    address bob = address(11); // 0x00...b

    function setUp() public {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        stateManager = new QuarkStateManager();
        console.log("QuarkStateManager deployed to: %s", address(stateManager));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));

        alice = vm.addr(alicePrivateKey);
        wallet = new QuarkWallet(alice, address(0), codeJar, stateManager);
    }

    function incrementCounterOperation(QuarkWallet targetWallet) public returns (QuarkWallet.QuarkOperation memory) {
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");

        return new QuarkOperationHelper().newBasicOpWithCalldata(
            targetWallet,
            incrementer,
            abi.encodeWithSignature("incrementCounter(address)", counter),
            ScriptType.ScriptSource
        );
    }

    function testExecuteQuarkOperation() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        assertEq(counter.number(), 0);

        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(wallet);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);

        // counter has incremented
        assertEq(counter.number(), 3);

        // nonce is spent
        assertEq(stateManager.isNonceSet(address(wallet), op.nonce), true);
    }

    function testRevertsForBadCode() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        assertEq(counter.number(), 0);

        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(wallet);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // bad actor modifies script source to selfdestruct the wallet
        op.scriptSource = hex"6000ff";

        // gas: meter execute
        vm.resumeGasMetering();

        // submitter calls executeQuarkOperation with the signed op, but they manipulate the code
        vm.expectRevert(QuarkWallet.BadSignatory.selector);
        wallet.executeQuarkOperation(op, v, r, s);

        // counter is unchanged
        assertEq(counter.number(), 0);

        // nonce is not spent
        assertEq(stateManager.isNonceSet(address(wallet), op.nonce), false);
    }

    function testRevertsForBadCalldata() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        assertEq(counter.number(), 0);

        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(wallet);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // submitter calls executeQuarkOperation with the signed op, but they manipulate the calldata
        op.scriptCalldata = abi.encodeWithSignature("decrementCounter(address)", counter);
        vm.expectRevert(QuarkWallet.BadSignatory.selector);

        // gas: meter execute
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);

        // counter is unchanged
        assertEq(counter.number(), 0);

        // nonce is not spent
        assertEq(stateManager.isNonceSet(address(wallet), op.nonce), false);
    }

    function testRevertsForBadExpiry() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        assertEq(counter.number(), 0);

        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(wallet);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // submitter calls executeQuarkOperation with the signed op, but they manipulate the expiry
        op.expiry += 1;
        vm.expectRevert(QuarkWallet.BadSignatory.selector);

        // gas: meter execute
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);

        // counter is unchanged
        assertEq(counter.number(), 0);

        // alice's nonce is not incremented
        assertEq(stateManager.nextNonce(address(wallet)), op.nonce);
    }

    function testRevertsOnReusedNonce() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        assertEq(counter.number(), 0);

        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(wallet);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // gas: meter execute
        vm.resumeGasMetering();

        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(counter.number(), 3);
        assertEq(stateManager.nextNonce(address(wallet)), op.nonce + 1);

        // submitter tries to reuse the same signature twice, for a non-replayable operation
        vm.expectRevert(QuarkStateManager.NonceAlreadySet.selector);
        wallet.executeQuarkOperation(op, v, r, s);
    }

    function testRevertsForExpiredSignature() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        assertEq(counter.number(), 0);

        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(wallet);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // the expiry block arrives
        vm.warp(op.expiry);

        // submitter calls executeQuarkOperation with an expired signature
        vm.expectRevert(QuarkWallet.SignatureExpired.selector);

        // gas: meter execute
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(counter.number(), 0);
        assertEq(stateManager.nextNonce(address(wallet)), op.nonce);
    }

    function testRevertsInvalidS() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        assertEq(counter.number(), 0);

        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(wallet);
        (uint8 v, bytes32 r, /* bytes32 s */ ) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // 1 greater than the max value of s
        bytes32 invalidS = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A1;

        // submitter calls executeQuarkOperation with invalid `s` value
        vm.expectRevert(QuarkWallet.InvalidSignature.selector);

        // gas: meter execute
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, invalidS);

        assertEq(counter.number(), 0);
        assertEq(stateManager.nextNonce(address(wallet)), op.nonce);
    }

    function testNonceIsNotSetForReplayableOperation() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");

        assertEq(counter.number(), 0);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            incrementer,
            abi.encodeWithSignature("incrementCounterReplayable(address)", counter),
            ScriptType.ScriptSource
        );

        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // submitter calls executeQuarkOperation with the signed operation
        // gas: meter execute
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);

        // counter is incremented
        assertEq(counter.number(), 3);

        // nonce is NOT spent; the operation is replayable
        assertEq(stateManager.isNonceSet(address(wallet), op.nonce), false);

        // submitter executes the operation a second time
        wallet.executeQuarkOperation(op, v, r, s);

        // counter is incremented
        assertEq(counter.number(), 6);

        // nonce is still not spent
        assertEq(stateManager.isNonceSet(address(wallet), op.nonce), false);
    }

    function testRevertBadRequirements() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");
        bytes memory executeWithRequirements =
            new YulHelper().getDeployed("ExecuteWithRequirements.sol/ExecuteWithRequirements.json");

        address incrementerAddress = codeJar.saveCode(incrementer);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            executeWithRequirements,
            abi.encodeCall(
                ExecuteWithRequirements.runWithRequirements,
                (new uint96[](0), incrementerAddress, abi.encodeWithSignature("incrementCounter(address)", counter))
            ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // submitter alters the requirements
        uint96[] memory badRequirements = new uint96[](1);
        badRequirements[0] = 123;
        op.scriptCalldata = abi.encodeCall(
            ExecuteWithRequirements.runWithRequirements,
            (badRequirements, incrementerAddress, abi.encodeWithSignature("incrementCounter(address)", counter))
        );

        // submitter cannot execute the operation because the signature will not match
        vm.expectRevert(QuarkWallet.BadSignatory.selector);

        // gas: meter execute
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(counter.number(), 0);
        assertEq(stateManager.nextNonce(address(wallet)), op.nonce);
    }

    function testRequirements() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");
        bytes memory executeWithRequirements =
            new YulHelper().getDeployed("ExecuteWithRequirements.sol/ExecuteWithRequirements.json");

        address incrementerAddress = codeJar.saveCode(incrementer);

        QuarkWallet.QuarkOperation memory firstOp = incrementCounterOperation(wallet);
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, wallet, firstOp);

        uint96[] memory requirements = new uint96[](1);
        requirements[0] = firstOp.nonce;
        QuarkWallet.QuarkOperation memory dependentOp = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            executeWithRequirements,
            abi.encodeCall(
                ExecuteWithRequirements.runWithRequirements,
                (requirements, incrementerAddress, abi.encodeWithSignature("incrementCounter(address)", counter))
            ),
            ScriptType.ScriptSource
        );

        dependentOp.nonce = firstOp.nonce + 1;

        (uint8 v2, bytes32 r2, bytes32 s2) = new SignatureHelper().signOp(alicePrivateKey, wallet, dependentOp);

        // attempting to execute the second operation first reverts
        vm.expectRevert(abi.encodeWithSelector(ExecuteWithRequirements.RequirementNotMet.selector, firstOp.nonce));

        // gas: meter execute
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(dependentOp, v2, r2, s2);

        // but once the first operation is executed...
        wallet.executeQuarkOperation(firstOp, v1, r1, s1);
        assertEq(counter.number(), 3);
        // the second can be executed
        wallet.executeQuarkOperation(dependentOp, v2, r2, s2);
        // and its effect can be observed
        assertEq(counter.number(), 6);
    }
}