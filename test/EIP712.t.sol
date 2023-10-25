pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/console.sol";

import {Test} from "forge-std/Test.sol";
import {QuarkWallet} from "../src/QuarkWallet.sol";
import {CodeJar} from "../src/CodeJar.sol";
import {Counter} from "./lib/Counter.sol";
import {YulHelper} from "./lib/YulHelper.sol";
import {QuarkStateManager} from "../src/QuarkStateManager.sol";
import {SignatureHelper} from "./lib/SignatureHelper.sol";
import {ExecuteWithRequirements} from "./lib/ExecuteWithRequirements.sol";

contract EIP712Test is Test {
    CodeJar public codeJar;
    Counter public counter;
    QuarkWallet public wallet;
    QuarkStateManager public stateManager;

    uint256 alicePrivateKey = 0xa11ce;
    address alice; // see setup()
    address bob = address(11); // 0x00...b
    address charlie = address(12); // 0x00...c

    function setUp() public {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        stateManager = new QuarkStateManager();
        console.log("QuarkStateManager deployed to: %s", address(stateManager));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));

        alice = vm.addr(alicePrivateKey);
        wallet = new QuarkWallet(alice, codeJar, stateManager);
    }

    function incrementCounterOperation(uint256 nonce, uint256 expiry)
        public
        returns (QuarkWallet.QuarkOperation memory)
    {
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: incrementer,
            scriptCalldata: abi.encodeWithSignature("incrementCounter(address)", counter),
            nonce: nonce,
            expiry: expiry,
            allowCallback: false
        });

        return op;
    }

    function testExecuteQuarkOperation() public {
        assertEq(counter.number(), 0);
        assertEq(wallet.nextUnusedNonce(), 1);

        uint256 nonce = wallet.nextUnusedNonce();
        uint256 expiry = block.timestamp + 1000;

        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // bob calls executeOp with the signed operation
        vm.prank(bob);
        wallet.executeQuarkOperation(op, v, r, s);

        // counter has incremented
        assertEq(counter.number(), 3);

        // nonce is spent
        assertEq(stateManager.isNonceSet(address(wallet), nonce), true);
    }

    function testRevertsForBadCode() public {
        assertEq(counter.number(), 0);
        assertEq(wallet.nextUnusedNonce(), 1);

        uint256 nonce = wallet.nextUnusedNonce();
        uint256 expiry = block.timestamp + 1000;

        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // bob calls executeQuarkOperation with the signed op, but he manipulates the code
        op.scriptSource = new YulHelper().getDeployed("GetOwner.sol/GetOwner.json");
        vm.prank(bob);
        vm.expectRevert(QuarkWallet.BadSignatory.selector);
        wallet.executeQuarkOperation(op, v, r, s);

        // counter is unchanged
        assertEq(counter.number(), 0);

        // nonce is not spent
        assertEq(stateManager.isNonceSet(address(wallet), nonce), false);
    }

    function testRevertsForBadCalldata() public {
        assertEq(counter.number(), 0);
        assertEq(wallet.nextUnusedNonce(), 1);

        uint256 nonce = wallet.nextUnusedNonce();
        uint256 expiry = block.timestamp + 1000;

        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // bob calls executeQuarkOperation with the signed op, but he manipulates the calldata
        op.scriptCalldata = abi.encodeWithSignature("decrementCounter(address)", counter);
        vm.prank(bob);
        vm.expectRevert(QuarkWallet.BadSignatory.selector);
        wallet.executeQuarkOperation(op, v, r, s);

        // counter is unchanged
        assertEq(counter.number(), 0);

        // nonce is not spent
        assertEq(stateManager.isNonceSet(address(wallet), nonce), false);
    }

    function testRevertsForBadExpiry() public {
        assertEq(counter.number(), 0);
        assertEq(wallet.nextUnusedNonce(), 1);

        uint256 nonce = wallet.nextUnusedNonce();
        uint256 expiry = block.timestamp + 1000;

        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // bob calls executeQuarkOperation with the signed op, but he manipulates the expiry
        op.expiry += 1;
        vm.prank(bob);
        vm.expectRevert(QuarkWallet.BadSignatory.selector);
        wallet.executeQuarkOperation(op, v, r, s);

        // counter is unchanged
        assertEq(counter.number(), 0);

        // alice's nonce is not incremented
        assertEq(wallet.nextUnusedNonce(), 1);
    }

    function testRevertsOnReusedNonce() public {
        assertEq(counter.number(), 0);
        assertEq(wallet.nextUnusedNonce(), 1);

        uint256 nonce = wallet.nextUnusedNonce();
        uint256 expiry = block.timestamp + 1000;

        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // bob calls executeQuarkOperation with the signature
        vm.startPrank(bob);
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(counter.number(), 3);
        assertEq(wallet.nextUnusedNonce(), 2);

        // bob tries to reuse the same signature twice
        vm.expectRevert(QuarkWallet.InvalidNonce.selector);
        wallet.executeQuarkOperation(op, v, r, s);

        vm.stopPrank();
    }

    function testRevertsForExpiredSignature() public {
        assertEq(counter.number(), 0);
        assertEq(wallet.nextUnusedNonce(), 1);

        uint256 nonce = wallet.nextUnusedNonce();
        uint256 expiry = block.timestamp + 1000;

        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // the expiry block arrives
        vm.warp(expiry);

        // bob calls executeQuarkOperation with the signature after the expiry
        vm.prank(bob);
        vm.expectRevert(QuarkWallet.SignatureExpired.selector);
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(counter.number(), 0);
        assertEq(wallet.nextUnusedNonce(), 1);
    }

    function testRevertsInvalidS() public {
        assertEq(counter.number(), 0);
        assertEq(wallet.nextUnusedNonce(), 1);

        uint256 nonce = wallet.nextUnusedNonce();
        uint256 expiry = block.timestamp + 1000;

        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // 1 greater than the max value of s
        bytes32 invalidS = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A1;

        // bob calls executeQuarkOperation with invalid `s` value
        vm.prank(bob);
        vm.expectRevert(QuarkWallet.InvalidSignatureS.selector);
        wallet.executeQuarkOperation(op, v, r, invalidS);

        assertEq(counter.number(), 0);
        assertEq(wallet.nextUnusedNonce(), 1);
    }

    function testNonceIsNotSetForReplayableOperation() public {
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");

        assertEq(counter.number(), 0);
        assertEq(wallet.nextUnusedNonce(), 1);

        uint256 nonce = wallet.nextUnusedNonce();
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: incrementer,
            scriptCalldata: abi.encodeWithSignature("incrementCounterReplayable(address)", counter),
            nonce: nonce,
            expiry: block.timestamp + 1000,
            allowCallback: false
        });

        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // bob calls executeOp with the signed operation
        vm.prank(bob);
        wallet.executeQuarkOperation(op, v, r, s);

        // counter is incremented
        assertEq(counter.number(), 3);

        // nonce is NOT spent
        assertEq(stateManager.isNonceSet(address(wallet), nonce), false);

        // bob executes the operation a second time
        vm.prank(bob);
        wallet.executeQuarkOperation(op, v, r, s);

        // counter is incremented
        assertEq(counter.number(), 6);

        // nonce is still not spent
        assertEq(stateManager.isNonceSet(address(wallet), nonce), false);
    }

    // TODO: rewrite these tests to use requirements implemented in the script itself
    function testRevertBadRequirements() public {
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");
        address incrementerAddress = codeJar.saveCode(incrementer);

        bytes memory executeWithRequirements =
            new YulHelper().getDeployed("ExecuteWithRequirements.sol/ExecuteWithRequirements.json");

        uint256 nonce = wallet.nextUnusedNonce();
        uint256 expiry = block.timestamp + 1000;

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: executeWithRequirements,
            scriptCalldata: abi.encodeCall(
                ExecuteWithRequirements.runWithRequirements,
                (new uint256[](0), incrementerAddress, abi.encodeWithSignature("incrementCounter(address)", counter))
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: block.timestamp + 1000,
            allowCallback: false
        });
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // bob calls executeQuarkOperation with the altered requirements
        vm.prank(bob);
        uint256[] memory badRequirements = new uint256[](1);
        badRequirements[0] = 123;
        op.scriptCalldata = abi.encodeCall(
            ExecuteWithRequirements.runWithRequirements,
            (badRequirements, incrementerAddress, abi.encodeWithSignature("incrementCounter(address)", counter))
        );

        // bob cannot submit the operation because the signature will not match
        vm.expectRevert(QuarkWallet.BadSignatory.selector);
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(counter.number(), 0);
        assertEq(wallet.nextUnusedNonce(), 1);
    }

    function testRequirements() public {
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");
        address incrementerAddress = codeJar.saveCode(incrementer);

        bytes memory executeWithRequirements =
            new YulHelper().getDeployed("ExecuteWithRequirements.sol/ExecuteWithRequirements.json");

        vm.startPrank(bob);

        uint256 nonce = wallet.nextUnusedNonce();
        uint256 expiry = block.timestamp + 1000;

        QuarkWallet.QuarkOperation memory firstOp = incrementCounterOperation(nonce, expiry);
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, wallet, firstOp);

        uint256[] memory requirements = new uint[](1);
        requirements[0] = firstOp.nonce;
        QuarkWallet.QuarkOperation memory dependentOp = QuarkWallet.QuarkOperation({
            scriptSource: executeWithRequirements,
            scriptCalldata: abi.encodeCall(
                ExecuteWithRequirements.runWithRequirements,
                (requirements, incrementerAddress, abi.encodeWithSignature("incrementCounter(address)", counter))
                ),
            nonce: nonce + 1,
            expiry: block.timestamp + 1000,
            allowCallback: false
        });
        (uint8 v2, bytes32 r2, bytes32 s2) = new SignatureHelper().signOp(alicePrivateKey, wallet, dependentOp);

        // attempting to execute the second operation first reverts
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector,
                abi.encodeWithSelector(ExecuteWithRequirements.RequirementNotMet.selector, nonce)
            )
        );
        wallet.executeQuarkOperation(dependentOp, v2, r2, s2);

        // but once the first operation is executed...
        wallet.executeQuarkOperation(firstOp, v1, r1, s1);

        // the second can be executed
        wallet.executeQuarkOperation(dependentOp, v2, r2, s2);

        vm.stopPrank();
    }
}
