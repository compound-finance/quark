// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/console.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";
import {QuarkWallet, QuarkWalletStandalone, QuarkWalletMetadata} from "quark-core/src/QuarkWallet.sol";

import {SignatureHelper} from "test/lib/SignatureHelper.sol";

import {Logger} from "test/lib/Logger.sol";
import {Counter} from "test/lib/Counter.sol";
import {EmptyCode} from "test/lib/EmptyCode.sol";
import {Permit2, Permit2Helper} from "test/lib/Permit2Helper.sol";
import {EIP1271Signer, EIP1271Reverter} from "test/lib/EIP1271Signer.sol";

contract isValidSignatureTest is Test {
    CodeJar public codeJar;
    QuarkWallet aliceWallet;
    QuarkWallet bobWallet;
    QuarkStateManager public stateManager;
    Permit2 permit2;

    bytes4 internal constant EIP_1271_MAGIC_VALUE = 0x1626ba7e;

    bytes32 internal constant TEST_TYPEHASH = keccak256("Test(uint256 a,uint256 b,uint256 c)");

    uint256 alicePrivateKey = 0xa11ce;
    address alice; // see setup()
    uint256 bobPrivateKey = 0xb0b;
    address bob; // see setup()

    // Contract address on mainnet
    address constant PERMIT2_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    function setUp() public {
        // Fork setup
        vm.createSelectFork(
            string.concat(
                "https://node-provider.compound.finance/ethereum-mainnet/", vm.envString("NODE_PROVIDER_BYPASS_KEY")
            ),
            18429607 // 2023-10-25 13:24:00 PST
        );

        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        stateManager = new QuarkStateManager();
        console.log("QuarkStateManager deployed to: %s", address(stateManager));

        alice = vm.addr(alicePrivateKey);
        aliceWallet = new QuarkWalletStandalone(alice, address(0), codeJar, stateManager);

        bob = vm.addr(bobPrivateKey);
        bobWallet = new QuarkWalletStandalone(bob, address(0), codeJar, stateManager);

        permit2 = Permit2(PERMIT2_ADDRESS);
    }

    function createTestSignature(uint256 privateKey, QuarkWallet wallet) internal returns (bytes32, bytes memory) {
        bytes32 structHash = keccak256(abi.encode(TEST_TYPEHASH, 1, 2, 3));
        bytes32 digest =
            keccak256(abi.encodePacked("\x19\x01", new SignatureHelper().domainSeparator(address(wallet)), structHash));
        bytes32 quarkMsgDigest = aliceWallet.getMessageHashForQuark(abi.encode(digest));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, quarkMsgDigest);
        return (digest, abi.encodePacked(r, s, v));
    }

    function createPermit2Signature(uint256 privateKey, Permit2Helper.PermitSingle memory permitSingle)
        internal
        returns (bytes32, bytes memory)
    {
        bytes32 domainSeparator = Permit2Helper.DOMAIN_SEPARATOR(PERMIT2_ADDRESS);
        bytes32 digest = Permit2Helper._hashTypedData(Permit2Helper.hash(permitSingle), domainSeparator);
        bytes32 quarkMsgDigest = aliceWallet.getMessageHashForQuark(abi.encode(digest));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, quarkMsgDigest);
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
        // If v == 27, add 1 to it to make it invalid. If v == 28, subtract 1 from it to make it invalid.
        aliceWallet.isValidSignature(digest, abi.encodePacked(r, s, v - 1));
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

    function testRevertsForMessageWithoutDomainTypehash() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();

        bytes32 structHash = keccak256(abi.encode(TEST_TYPEHASH, 1, 2, 3));
        // We skip the step of encoding a domain separator around the message
        bytes32 quarkMsgDigest = aliceWallet.getMessageHashForQuark(abi.encode(structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, quarkMsgDigest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // gas: meter execute
        vm.resumeGasMetering();

        vm.expectRevert(QuarkWallet.BadSignatory.selector);
        aliceWallet.isValidSignature(quarkMsgDigest, signature);
    }

    /* wallet owned by smart contract  */

    function testReturnsMagicValueForValidSignature() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();

        // QuarkWallet is owned by a smart contract that always approves signatures
        EIP1271Signer signatureApprover = new EIP1271Signer(true);
        QuarkWallet contractWallet =
            new QuarkWalletStandalone(address(signatureApprover), address(0), codeJar, stateManager);
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
        QuarkWallet contractWallet =
            new QuarkWalletStandalone(address(signatureApprover), address(0), codeJar, stateManager);
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
        QuarkWallet contractWallet =
            new QuarkWalletStandalone(address(signatureApprover), address(0), codeJar, stateManager);
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

        address emptyCodeContract = address(new EmptyCode());
        QuarkWallet contractWallet = new QuarkWalletStandalone(emptyCodeContract, address(0), codeJar, stateManager);
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

    /* ===== re-use signature tests ===== */

    function testRevertsForPermit2SignatureReuse() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        QuarkWallet aliceWallet2 = new QuarkWalletStandalone(alice, address(0), codeJar, stateManager);

        Permit2Helper.PermitDetails memory permitDetails = Permit2Helper.PermitDetails({
            token: USDC,
            amount: 1_000e6,
            expiration: uint48(block.timestamp + 100),
            nonce: 0
        });
        Permit2Helper.PermitSingle memory permitSingle =
            Permit2Helper.PermitSingle({details: permitDetails, spender: bob, sigDeadline: block.timestamp + 100});
        ( /* bytes32 digest */ , bytes memory signature) = createPermit2Signature(alicePrivateKey, permitSingle);

        // gas: meter execute
        vm.resumeGasMetering();

        assertEq(permit2.allowance(address(aliceWallet), USDC, bob), 0);
        assertEq(permit2.allowance(address(aliceWallet2), USDC, bob), 0);

        permit2.permit(address(aliceWallet), permitSingle, signature);

        // Re-using the signature for a different one of Alice's wallet will revert
        vm.expectRevert(QuarkWallet.BadSignatory.selector);
        permit2.permit(address(aliceWallet2), permitSingle, signature);

        // Allowances are only set for Alice's first wallet
        assertNotEq(permit2.allowance(address(aliceWallet), USDC, bob), 0);
        assertEq(permit2.allowance(address(aliceWallet2), USDC, bob), 0);
    }

    function testRevertsForPermit2SignatureWithoutDomainTypehash() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();

        Permit2Helper.PermitDetails memory permitDetails = Permit2Helper.PermitDetails({
            token: USDC,
            amount: 1_000e6,
            expiration: uint48(block.timestamp + 100),
            nonce: 0
        });
        Permit2Helper.PermitSingle memory permitSingle =
            Permit2Helper.PermitSingle({details: permitDetails, spender: bob, sigDeadline: block.timestamp + 100});
        // We skip the step of encoding a domain separator around the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, Permit2Helper.hash(permitSingle));
        bytes memory signature = abi.encodePacked(r, s, v);

        // gas: meter execute
        vm.resumeGasMetering();

        assertEq(permit2.allowance(address(aliceWallet), USDC, bob), 0);

        // Signature is invalid
        vm.expectRevert(QuarkWallet.BadSignatory.selector);
        permit2.permit(address(aliceWallet), permitSingle, signature);

        assertEq(permit2.allowance(address(aliceWallet), USDC, bob), 0);
    }
}
