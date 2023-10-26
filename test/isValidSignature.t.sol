pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/console.sol";

import {QuarkWallet} from "../src/QuarkWallet.sol";
import {QuarkStateManager} from "../src/QuarkStateManager.sol";
import {CodeJar} from "../src/CodeJar.sol";
import {Counter} from "./lib/Counter.sol";
import {EIP1271Signer} from "./lib/EIP1271Signer.sol";

contract isValidSignatureTest is Test {
    CodeJar public codeJar;
    QuarkWallet aliceWallet;
    QuarkWallet bobWallet;
    QuarkStateManager public stateManager;

    bytes4 internal constant EIP_1271_MAGIC_VALUE = 0x1626ba7e;

    bytes32 internal constant TEST_TYPEHASH = keccak256("Test(uint256 a,uint256 b,uint256 c)");

    uint256 alicePrivateKey = 0xa11ce;
    address alice; // see setup()
    uint256 bobPrivateKey = 0xb0b;
    address bob; // see setup()

    function setUp() public {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        stateManager = new QuarkStateManager();
        console.log("QuarkStateManager deployed to: %s", address(stateManager));

        alice = vm.addr(alicePrivateKey);
        aliceWallet = new QuarkWallet(alice, codeJar, stateManager);

        bob = vm.addr(bobPrivateKey);
        bobWallet = new QuarkWallet(bob, codeJar, stateManager);
    }

    function createTestSignature(uint256 privateKey, QuarkWallet wallet)
        internal
        view
        returns (bytes32, bytes memory)
    {
        bytes32 structHash = keccak256(abi.encode(TEST_TYPEHASH, 1, 2, 3));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", wallet.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return (digest, abi.encodePacked(r, s, v));
    }

    /* wallet owned by EOA  */
    function testIsValidSignatureForEOAOwner() public {
        (bytes32 digest, bytes memory signature) = createTestSignature(alicePrivateKey, aliceWallet);
        assertEq(aliceWallet.isValidSignature(digest, signature), EIP_1271_MAGIC_VALUE);
    }

    function testRevertsIfSignatureExceeds65Bytes() public {
        (bytes32 digest, bytes memory signature) = createTestSignature(alicePrivateKey, aliceWallet);
        signature = bytes.concat(signature, bytes("1"));
        vm.expectRevert(QuarkWallet.InvalidSignature.selector);
        aliceWallet.isValidSignature(digest, signature);
    }

    function testRevertsForInvalidSignatureS() public {
        bytes32 structHash = keccak256(abi.encode(TEST_TYPEHASH, 1, 2, 3));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", aliceWallet.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 _s) = vm.sign(alicePrivateKey, digest);

        // 1 greater than the max value of s
        bytes32 invalidS = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A1;

        vm.expectRevert(QuarkWallet.InvalidSignatureS.selector);
        aliceWallet.isValidSignature(digest, abi.encodePacked(r, invalidS, v));
    }

    function testRevertsForInvalidSignature() public {
        bytes32 structHash = keccak256(abi.encode(TEST_TYPEHASH, 1, 2, 3));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", aliceWallet.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);

        vm.expectRevert(QuarkWallet.BadSignatory.selector);
        aliceWallet.isValidSignature(digest, abi.encodePacked(r, s, v + 1));
    }

    function testRevertsForWrongSigner() public {
        // signature from bob
        (bytes32 digest, bytes memory signature) = createTestSignature(bobPrivateKey, bobWallet);
        vm.expectRevert(QuarkWallet.BadSignatory.selector);
        aliceWallet.isValidSignature(digest, signature);
    }

    /* wallet owned by smart contract  */
    function testReturnsMagicValueForValidSignature() public {
        // QuarkWallet is owned by a smart contract that always approves signatures
        EIP1271Signer signatureApprover = new EIP1271Signer(true);
        QuarkWallet contractWallet = new QuarkWallet(address(signatureApprover), codeJar, stateManager);
        // signature from bob; doesn't matter because the EIP1271Signer will approve anything
        (bytes32 digest, bytes memory signature) = createTestSignature(bobPrivateKey, bobWallet);
        assertEq(contractWallet.isValidSignature(bytes32(""), signature), EIP_1271_MAGIC_VALUE);
    }

    function testRevertsIfSignerContractReturnsFalse() public {
        // QuarkWallet is owned by a smart contract that always rejects signatures
        EIP1271Signer signatureApprover = new EIP1271Signer(false);
        QuarkWallet contractWallet = new QuarkWallet(address(signatureApprover), codeJar, stateManager);
        // signature from bob; doesn't matter because the EIP1271Signer will reject everything
        (bytes32 digest, bytes memory signature) = createTestSignature(bobPrivateKey, bobWallet);
        vm.expectRevert(QuarkWallet.InvalidSignature.selector);
        contractWallet.isValidSignature(bytes32(""), signature);
    }
}
