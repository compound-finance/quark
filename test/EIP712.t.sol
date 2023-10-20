pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/console.sol";

import { Test } from "forge-std/Test.sol";
import { QuarkWallet } from "../src/QuarkWallet.sol";
import { CodeJar} from "../src/CodeJar.sol";
import { Counter } from "./lib/Counter.sol";
import { YulHelper } from "./lib/YulHelper.sol";
import { QuarkStorageManager } from "../src/QuarkStorageManager.sol";

contract EIP712Test is Test {
    CodeJar public codeJar;
    Counter public counter;
    QuarkWallet public wallet;
    QuarkStorageManager public storageManager;

    uint256 alicePrivateKey = 0xa11ce;
    address alice; // see setup()
    address bob = address(11); // 0x00...b
    address charlie = address(12); // 0x00...c

    bytes32 internal constant QUARK_OPERATION_TYPEHASH = keccak256("QuarkOperation(bytes scriptSource,bytes scriptCalldata,uint256 nonce,uint256 expiry,bool allowCallback)");

    function setUp() public {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        storageManager = new QuarkStorageManager();
        console.log("QuarkStorageManager deployed to: %s", address(storageManager));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));

        alice = vm.addr(alicePrivateKey);
        wallet = new QuarkWallet(alice, codeJar, storageManager);
    }

    function aliceSignature(QuarkWallet.QuarkOperation memory op) internal view returns (uint8, bytes32, bytes32) {
        bytes32 structHash = keccak256(abi.encode(QUARK_OPERATION_TYPEHASH, op.scriptSource, op.scriptCalldata, op.nonce, op.expiry, op.allowCallback));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", wallet.DOMAIN_SEPARATOR(), structHash));
        return vm.sign(alicePrivateKey, digest);
    }

    function incrementCounterOperation(uint256 nonce, uint256 expiry) public returns (QuarkWallet.QuarkOperation memory) {
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
        assertEq(wallet.nextUnusedNonce(), 0);

        uint256 nonce = wallet.nextUnusedNonce();
        uint256 expiry = block.timestamp + 1000;

        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = aliceSignature(op);

        // bob calls executeOp with the signed operation
        vm.prank(bob);
        wallet.executeQuarkOperation(op, v, r, s);

        // counter has incremented
        assertEq(counter.number(), 3);

        // nonce is spent
        assertEq(storageManager.isNonceSet(address(wallet), nonce), true);
    }

    function testRevertsForBadCode() public {
        assertEq(counter.number(), 0);
        assertEq(wallet.nextUnusedNonce(), 0);

        uint256 nonce = wallet.nextUnusedNonce();
        uint256 expiry = block.timestamp + 1000;

        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = aliceSignature(op);

        // bob calls executeQuarkOperation with the signed op, but he manipulates the code
        op.scriptSource = new YulHelper().getDeployed("GetOwner.sol/GetOwner.json");
        vm.prank(bob);
        vm.expectRevert(QuarkWallet.BadSignatory.selector);
        wallet.executeQuarkOperation(op, v, r, s);

        // counter is unchanged
        assertEq(counter.number(), 0);

        // nonce is not spent
        assertEq(storageManager.isNonceSet(address(wallet), nonce), false);
    }

    function testRevertsForBadCalldata() public {
        assertEq(counter.number(), 0);
        assertEq(wallet.nextUnusedNonce(), 0);

        uint256 nonce = wallet.nextUnusedNonce();
        uint256 expiry = block.timestamp + 1000;

        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = aliceSignature(op);

        // bob calls executeQuarkOperation with the signed op, but he manipulates the calldata
        op.scriptCalldata = abi.encodeWithSignature("decrementCounter(address)", counter);
        vm.prank(bob);
        vm.expectRevert(QuarkWallet.BadSignatory.selector);
        wallet.executeQuarkOperation(op, v, r, s);

        // counter is unchanged
        assertEq(counter.number(), 0);

        // nonce is not spent
        assertEq(storageManager.isNonceSet(address(wallet), nonce), false);
    }

    function testRevertsForBadExpiry() public {
        assertEq(counter.number(), 0);
        assertEq(wallet.nextUnusedNonce(), 0);

        uint256 nonce = wallet.nextUnusedNonce();
        uint256 expiry = block.timestamp + 1000;

        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = aliceSignature(op);

        // bob calls executeQuarkOperation with the signed op, but he manipulates the expiry
        op.expiry += 1;
        vm.prank(bob);
        vm.expectRevert(QuarkWallet.BadSignatory.selector);
        wallet.executeQuarkOperation(op, v, r, s);

        // counter is unchanged
        assertEq(counter.number(), 0);

        // alice's nonce is not incremented
        assertEq(wallet.nextUnusedNonce(), 0);
    }

    function testRevertsOnReusedNonce() public {
        assertEq(counter.number(), 0);
        assertEq(wallet.nextUnusedNonce(), 0);

        uint256 nonce = wallet.nextUnusedNonce();
        uint256 expiry = block.timestamp + 1000;

        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = aliceSignature(op);

        // bob calls executeQuarkOperation with the signature
        vm.startPrank(bob);
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(counter.number(), 3);
        assertEq(wallet.nextUnusedNonce(), 1);

        // bob tries to reuse the same signature twice
        vm.expectRevert(QuarkWallet.InvalidNonce.selector);
        wallet.executeQuarkOperation(op, v, r, s);

        vm.stopPrank();
    }

    function testRevertsForExpiredSignature() public {
        assertEq(counter.number(), 0);
        assertEq(wallet.nextUnusedNonce(), 0);

        uint256 nonce = wallet.nextUnusedNonce();
        uint256 expiry = block.timestamp + 1000;

        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = aliceSignature(op);

        // the expiry block arrives
        vm.warp(expiry);

        // bob calls executeQuarkOperation with the signature after the expiry
        vm.prank(bob);
        vm.expectRevert(QuarkWallet.SignatureExpired.selector);
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(counter.number(), 0);
        assertEq(wallet.nextUnusedNonce(), 0);
    }

    function testRevertsInvalidS() public {
        assertEq(counter.number(), 0);
        assertEq(wallet.nextUnusedNonce(), 0);

        uint256 nonce = wallet.nextUnusedNonce();
        uint256 expiry = block.timestamp + 1000;

        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = aliceSignature(op);

        // 1 greater than the max value of s
        bytes32 invalidS = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A1;

        // bob calls executeQuarkOperation with invalid `s` value
        vm.prank(bob);
        vm.expectRevert(QuarkWallet.InvalidSignatureS.selector);
        wallet.executeQuarkOperation(op, v, r, invalidS);

        assertEq(counter.number(), 0);
        assertEq(wallet.nextUnusedNonce(), 0);
    }
}
