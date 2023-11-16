pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/console.sol";

import {QuarkWallet, QuarkWalletMetadata} from "../src/QuarkWallet.sol";
import {QuarkStateManager} from "../src/QuarkStateManager.sol";
import {CodeJar} from "../src/CodeJar.sol";
import {Counter} from "./lib/Counter.sol";
import {EIP1271Signer, EIP1271Reverter} from "./lib/EIP1271Signer.sol";
import {SignatureHelper} from "./lib/SignatureHelper.sol";

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
        aliceWallet = new QuarkWallet(alice, address(0), codeJar, stateManager);

        bob = vm.addr(bobPrivateKey);
        bobWallet = new QuarkWallet(bob, address(0), codeJar, stateManager);
    }

    function createTestSignature(uint256 privateKey, QuarkWallet wallet)
        internal
        returns (bytes32, bytes memory)
    {
        bytes32 structHash = keccak256(abi.encode(TEST_TYPEHASH, 1, 2, 3));
        bytes32 digest =
            keccak256(abi.encodePacked("\x19\x01", new SignatureHelper().domainSeparator(address(wallet)), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return (digest, abi.encodePacked(r, s, v));
    }

    /* wallet owned by EOA  */
    function testIsValidSignatureForEOAOwner() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();

        (bytes32 digest, bytes memory signature) = createTestSignature(alicePrivateKey, aliceWallet);

        // gas: meter execute
        vm.resumeGasMetering();

        assertEq(aliceWallet.isValidSignature(digest, signature), EIP_1271_MAGIC_VALUE);
    }

    function testRevertsIfSignatureExceeds65Bytes() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();

        (bytes32 digest, bytes memory signature) = createTestSignature(alicePrivateKey, aliceWallet);
        signature = bytes.concat(signature, bytes("1"));

        // gas: meter execute
        vm.resumeGasMetering();

        vm.expectRevert(QuarkWallet.InvalidSignature.selector);
        aliceWallet.isValidSignature(digest, signature);
    }

    function testRevertsInvalidS() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();

        bytes32 structHash = keccak256(abi.encode(TEST_TYPEHASH, 1, 2, 3));
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", new SignatureHelper().domainSeparator(address(aliceWallet)), structHash)
        );
        (uint8 v, bytes32 r, /* bytes32 s */ ) = vm.sign(alicePrivateKey, digest);

        // 1 greater than the max value of s
        bytes32 invalidS = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A1;

        // gas: meter execute
        vm.resumeGasMetering();

        vm.expectRevert(QuarkWallet.InvalidSignature.selector);
        aliceWallet.isValidSignature(digest, abi.encodePacked(r, invalidS, v));
    }

    function testRevertsForInvalidSignature() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();

        bytes32 structHash = keccak256(abi.encode(TEST_TYPEHASH, 1, 2, 3));
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", new SignatureHelper().domainSeparator(address(aliceWallet)), structHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);

        // gas: meter execute
        vm.resumeGasMetering();

        vm.expectRevert(QuarkWallet.BadSignatory.selector);
        aliceWallet.isValidSignature(digest, abi.encodePacked(r, s, v + 1));
    }

    function testRevertsForWrongSigner() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();

        // signature from bob
        (bytes32 digest, bytes memory signature) = createTestSignature(bobPrivateKey, bobWallet);
        // gas: meter execute
        vm.resumeGasMetering();

        vm.expectRevert(QuarkWallet.BadSignatory.selector);
        aliceWallet.isValidSignature(digest, signature);
    }

    /* wallet owned by smart contract  */
    function testReturnsMagicValueForValidSignature() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();

        // QuarkWallet is owned by a smart contract that always approves signatures
        EIP1271Signer signatureApprover = new EIP1271Signer(true);
        QuarkWallet contractWallet = new QuarkWallet(address(signatureApprover), address(0), codeJar, stateManager);
        // signature from bob; doesn't matter because the EIP1271Signer will approve anything
        ( /* bytes32 digest */ , bytes memory signature) = createTestSignature(bobPrivateKey, bobWallet);
        // gas: meter execute
        vm.resumeGasMetering();

        assertEq(contractWallet.isValidSignature(bytes32(""), signature), EIP_1271_MAGIC_VALUE);
    }

    function testRevertsIfSignerContractDoesNotReturnMagic() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();

        // QuarkWallet is owned by a smart contract that always rejects signatures
        EIP1271Signer signatureApprover = new EIP1271Signer(false);
        QuarkWallet contractWallet = new QuarkWallet(address(signatureApprover), address(0), codeJar, stateManager);
        // signature from bob; doesn't matter because the EIP1271Signer will reject everything
        ( /* bytes32 digest */ , bytes memory signature) = createTestSignature(bobPrivateKey, bobWallet);
        // gas: meter execute
        vm.resumeGasMetering();

        vm.expectRevert(QuarkWallet.InvalidEIP1271Signature.selector);
        contractWallet.isValidSignature(bytes32(""), signature);
    }

    function testRevertsIfSignerContractReverts() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();

        // QuarkWallet is owned by a smart contract that always reverts
        EIP1271Reverter signatureApprover = new EIP1271Reverter();
        QuarkWallet contractWallet = new QuarkWallet(address(signatureApprover), address(0), codeJar, stateManager);
        // signature from bob; doesn't matter because the EIP1271Signer will revert
        ( /* bytes32 digest */ , bytes memory signature) = createTestSignature(bobPrivateKey, bobWallet);
        // gas: meter execute
        vm.resumeGasMetering();

        vm.expectRevert(QuarkWallet.InvalidEIP1271Signature.selector);
        contractWallet.isValidSignature(bytes32(""), signature);
    }

    function testRevertsForEmptyContract() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();

        address emptyCodeContract = codeJar.saveCode(hex"");
        QuarkWallet contractWallet = new QuarkWallet(emptyCodeContract, address(0), codeJar, stateManager);
        // signature from bob; doesn't matter because the empty contract will be treated as an EOA and revert
        ( /* bytes32 digest */ , bytes memory signature) = createTestSignature(bobPrivateKey, bobWallet);
        // gas: meter execute
        vm.resumeGasMetering();

        // call reverts with BadSignatory since the empty contract appears to
        // have no code; request will go down the code path for EIP-712
        // signatures and will revert as bad signature
        vm.expectRevert(QuarkWallet.BadSignatory.selector);
        contractWallet.isValidSignature(bytes32(""), signature);
    }
}
