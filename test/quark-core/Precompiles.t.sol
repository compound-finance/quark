// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "quark-core/src/CodeJar.sol";
import "quark-core/src/QuarkWallet.sol";
import "quark-core/src/QuarkStateManager.sol";

import "test/lib/YulHelper.sol";
import "test/lib/SignatureHelper.sol";
import "test/lib/PrecompileCaller.sol";
import "test/lib/QuarkOperationHelper.sol";

contract PrecompilesTest is Test {
    CodeJar public codeJar;
    QuarkStateManager public stateManager;

    uint256 alicePrivateKey = 0x8675309;
    address aliceAccount = vm.addr(alicePrivateKey);
    QuarkWallet aliceWallet; // see constructor()

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        stateManager = new QuarkStateManager();
        console.log("QuarkStateManager deployed to: %s", address(stateManager));

        aliceWallet = new QuarkWallet(aliceAccount, address(0), codeJar, stateManager);
        console.log("Alice signer: %s", aliceAccount);
        console.log("Alice wallet at: %s", address(aliceWallet));
    }

    /* ===== execution on Precompiles ===== */
    // Quark is no longer able call precompiles directly due to empty code check, so these tests are commented out

    function testPrecompileEcRecover() public {
        vm.pauseGasMetering();
        bytes memory preCompileCaller = new YulHelper().getDeployed("PrecompileCaller.sol/PrecompileCaller.json");
        bytes32 testHash = keccak256("test");
        (uint8 vt, bytes32 rt, bytes32 st) = vm.sign(alicePrivateKey, testHash);
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            preCompileCaller,
            abi.encodeCall(PrecompileCaller.ecrecoverCall, (testHash, vt, rt, st)),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
        vm.resumeGasMetering();
        bytes memory rawOut = aliceWallet.executeQuarkOperation(op, v, r, s);
        bytes memory output = abi.decode(rawOut, (bytes));
        assertEq(abi.decode(output, (address)), aliceAccount);
    }

    // function testPrecompileEcRecoverWithoutScript() public {
    //     vm.pauseGasMetering();
    //     bytes32 testHash = keccak256("test");
    //     (uint8 vt, bytes32 rt, bytes32 st) = vm.sign(alicePrivateKey, testHash);
    //     QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
    //         scriptAddress: address(0x1),
    //         scriptSource: "",
    //         scriptCalldata: abi.encode(testHash, vt, rt, st),
    //         nonce: aliceWallet.stateManager().nextNonce(address(aliceWallet)),
    //         expiry: block.timestamp + 1000
    //     });

    //     (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
    //     vm.resumeGasMetering();
    //     bytes memory rawOut = aliceWallet.executeQuarkOperation(op, v, r, s);
    //     assertEq(abi.decode(rawOut, (address)), aliceAccount);
    // }

    function testPrecompileSha256() public {
        vm.pauseGasMetering();
        bytes memory preCompileCaller = new YulHelper().getDeployed("PrecompileCaller.sol/PrecompileCaller.json");
        uint256 numberToHash = 123;
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            preCompileCaller,
            abi.encodeCall(PrecompileCaller.sha256Call, (numberToHash)),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
        vm.resumeGasMetering();
        bytes memory rawOut = aliceWallet.executeQuarkOperation(op, v, r, s);
        bytes memory output = abi.decode(rawOut, (bytes));
        assertEq(abi.decode(output, (bytes32)), sha256(abi.encodePacked(numberToHash)));
    }

    // function testPrecompileSha256WithoutScript() public {
    //     vm.pauseGasMetering();
    //     uint256 numberToHash = 123;
    //     QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
    //         scriptAddress: address(0x2),
    //         scriptSource: "",
    //         scriptCalldata: abi.encode(numberToHash),
    //         nonce: aliceWallet.stateManager().nextNonce(address(aliceWallet)),
    //         expiry: block.timestamp + 1000
    //     });

    //     (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
    //     vm.resumeGasMetering();
    //     bytes memory output = aliceWallet.executeQuarkOperation(op, v, r, s);
    //     assertEq(abi.decode(output, (bytes32)), sha256(abi.encodePacked(numberToHash)));
    // }

    function testPrecompileRipemd160() public {
        vm.pauseGasMetering();
        bytes memory preCompileCaller = new YulHelper().getDeployed("PrecompileCaller.sol/PrecompileCaller.json");
        bytes memory testBytes = abi.encodePacked(keccak256("test"));
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            preCompileCaller,
            abi.encodeCall(PrecompileCaller.ripemd160Call, (testBytes)),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
        vm.resumeGasMetering();
        bytes memory output = aliceWallet.executeQuarkOperation(op, v, r, s);
        assertEq(abi.decode(output, (bytes20)), ripemd160(testBytes));
    }

    // function testPrecompileRipemd160WithoutScript() public {
    //     vm.pauseGasMetering();
    //     bytes memory testBytes = abi.encodePacked(keccak256("test"));
    //     QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
    //         scriptAddress: address(0x3),
    //         scriptSource: "",
    //         scriptCalldata: testBytes,
    //         nonce: aliceWallet.stateManager().nextNonce(address(aliceWallet)),
    //         expiry: block.timestamp + 1000
    //     });
    //     (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
    //     vm.resumeGasMetering();
    //     bytes memory output = aliceWallet.executeQuarkOperation(op, v, r, s);
    //     assertEq(bytes20(abi.decode(output, (bytes32)) << 96), ripemd160(testBytes));
    // }

    function testPrecompileDataCopy() public {
        vm.pauseGasMetering();
        bytes memory preCompileCaller = new YulHelper().getDeployed("PrecompileCaller.sol/PrecompileCaller.json");
        bytes memory testBytes = abi.encodePacked(keccak256("testDataCopy"));
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            preCompileCaller,
            abi.encodeCall(PrecompileCaller.dataCopyCall, (testBytes)),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
        vm.resumeGasMetering();
        bytes memory output = aliceWallet.executeQuarkOperation(op, v, r, s);
        assertEq(abi.decode(output, (bytes)), testBytes);
    }

    // function testPrecompileDataCopyWithoutScript() public {
    //     vm.pauseGasMetering();
    //     bytes memory testBytes = abi.encodePacked(keccak256("testDataCopy"));
    //     QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
    //         scriptAddress: address(0x4),
    //         scriptSource: "",
    //         scriptCalldata: testBytes,
    //         nonce: aliceWallet.stateManager().nextNonce(address(aliceWallet)),
    //         expiry: block.timestamp + 1000
    //     });
    //     (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
    //     vm.resumeGasMetering();
    //     bytes memory output = aliceWallet.executeQuarkOperation(op, v, r, s);
    //     assertEq(output, testBytes);
    // }

    function testPrecompileBigModExp() public {
        vm.pauseGasMetering();
        bytes memory preCompileCaller = new YulHelper().getDeployed("PrecompileCaller.sol/PrecompileCaller.json");
        bytes32 base = bytes32(uint256(7));
        bytes32 exponent = bytes32(uint256(3));
        bytes32 modulus = bytes32(uint256(11));
        // 7^3 % 11 = 2
        bytes32 expected = bytes32(uint256(2));
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            preCompileCaller,
            abi.encodeCall(PrecompileCaller.bigModExpCall, (base, exponent, modulus)),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
        vm.resumeGasMetering();
        bytes memory output = aliceWallet.executeQuarkOperation(op, v, r, s);
        assertEq(abi.decode(output, (bytes32)), expected);
    }

    // function testPrecompileBigModExpWithoutScript() public {
    //     vm.pauseGasMetering();
    //     bytes32 base = bytes32(uint256(7));
    //     bytes32 exponent = bytes32(uint256(3));
    //     bytes32 modulus = bytes32(uint256(11));
    //     // 7^3 % 11 = 2
    //     bytes32 expected = bytes32(uint256(2));
    //     QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
    //         scriptAddress: address(0x5),
    //         scriptSource: "",
    //         scriptCalldata: abi.encode(uint256(0x20), uint256(0x20), uint256(0x20), base, exponent, modulus),
    //         nonce: aliceWallet.stateManager().nextNonce(address(aliceWallet)),
    //         expiry: block.timestamp + 1000
    //     });
    //     (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
    //     vm.resumeGasMetering();
    //     bytes memory output = aliceWallet.executeQuarkOperation(op, v, r, s);
    //     assertEq(abi.decode(output, (bytes32)), expected);
    // }

    function testPrecompileBn256Add() public {
        vm.pauseGasMetering();
        bytes memory preCompileCaller = new YulHelper().getDeployed("PrecompileCaller.sol/PrecompileCaller.json");
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            preCompileCaller,
            abi.encodeCall(PrecompileCaller.bn256AddCall, (uint256(1), uint256(2), uint256(1), uint256(2))),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
        vm.resumeGasMetering();
        bytes memory rawOut = aliceWallet.executeQuarkOperation(op, v, r, s);
        uint256[2] memory output = abi.decode(rawOut, (uint256[2]));
        assertEq(output[0], uint256(0x030644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd3));
        assertEq(output[1], uint256(0x15ed738c0e0a7c92e7845f96b2ae9c0a68a6a449e3538fc7ff3ebf7a5a18a2c4));
    }

    // function testPrecompileBn256AddWithoutScript() public {
    //     vm.pauseGasMetering();
    //     uint256[4] memory input;
    //     input[0] = uint256(1);
    //     input[1] = uint256(2);
    //     input[2] = uint256(1);
    //     input[3] = uint256(2);
    //     QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
    //         scriptAddress: address(0x6),
    //         scriptSource: "",
    //         scriptCalldata: abi.encode(input),
    //         nonce: aliceWallet.stateManager().nextNonce(address(aliceWallet)),
    //         expiry: block.timestamp + 1000
    //     });
    //     (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
    //     vm.resumeGasMetering();
    //     bytes memory rawOut = aliceWallet.executeQuarkOperation(op, v, r, s);
    //     uint256[2] memory output = abi.decode(rawOut, (uint256[2]));
    //     assertEq(output[0], uint256(0x030644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd3));
    //     assertEq(output[1], uint256(0x15ed738c0e0a7c92e7845f96b2ae9c0a68a6a449e3538fc7ff3ebf7a5a18a2c4));
    // }

    function testPrecompileBn256ScalarMul() public {
        vm.pauseGasMetering();
        bytes memory preCompileCaller = new YulHelper().getDeployed("PrecompileCaller.sol/PrecompileCaller.json");
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            preCompileCaller,
            abi.encodeCall(PrecompileCaller.bn256ScalarMulCall, (uint256(1), uint256(2), uint256(3))),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
        vm.resumeGasMetering();
        bytes memory rawOut = aliceWallet.executeQuarkOperation(op, v, r, s);
        uint256[2] memory output = abi.decode(rawOut, (uint256[2]));
        assertEq(output[0], uint256(0x0769bf9ac56bea3ff40232bcb1b6bd159315d84715b8e679f2d355961915abf0));
        assertEq(output[1], uint256(0x2ab799bee0489429554fdb7c8d086475319e63b40b9c5b57cdf1ff3dd9fe2261));
    }

    // function testPrecompileBn256ScalarMulWithoutScript() public {
    //     vm.pauseGasMetering();
    //     uint256[3] memory input;
    //     input[0] = uint256(1);
    //     input[1] = uint256(2);
    //     input[2] = uint256(3);
    //     QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
    //         scriptAddress: address(0x7),
    //         scriptSource: "",
    //         scriptCalldata: abi.encode(input),
    //         nonce: aliceWallet.stateManager().nextNonce(address(aliceWallet)),
    //         expiry: block.timestamp + 1000
    //     });
    //     (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
    //     vm.resumeGasMetering();
    //     bytes memory rawOut = aliceWallet.executeQuarkOperation(op, v, r, s);
    //     uint256[2] memory output = abi.decode(rawOut, (uint256[2]));
    //     assertEq(output[0], uint256(0x0769bf9ac56bea3ff40232bcb1b6bd159315d84715b8e679f2d355961915abf0));
    //     assertEq(output[1], uint256(0x2ab799bee0489429554fdb7c8d086475319e63b40b9c5b57cdf1ff3dd9fe2261));
    // }

    function testPrecompileBlake2F() public {
        vm.pauseGasMetering();
        bytes memory preCompileCaller = new YulHelper().getDeployed("PrecompileCaller.sol/PrecompileCaller.json");
        uint32 rounds = 12;

        bytes32[2] memory h;
        h[0] = hex"48c9bdf267e6096a3ba7ca8485ae67bb2bf894fe72f36e3cf1361d5f3af54fa5";
        h[1] = hex"d182e6ad7f520e511f6c3e2b8c68059b6bbd41fbabd9831f79217e1319cde05b";

        bytes32[4] memory m;
        m[0] = hex"6162630000000000000000000000000000000000000000000000000000000000";
        m[1] = hex"0000000000000000000000000000000000000000000000000000000000000000";
        m[2] = hex"0000000000000000000000000000000000000000000000000000000000000000";
        m[3] = hex"0000000000000000000000000000000000000000000000000000000000000000";

        bytes8[2] memory t;
        t[0] = hex"03000000";
        t[1] = hex"00000000";

        bool f = true;

        bytes32[2] memory expected;
        expected[0] = hex"ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d1";
        expected[1] = hex"7d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923";

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            preCompileCaller,
            abi.encodeCall(PrecompileCaller.blake2FCall, (rounds, h, m, t, f)),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
        vm.resumeGasMetering();
        bytes memory rawOut = aliceWallet.executeQuarkOperation(op, v, r, s);
        bytes32[2] memory output = abi.decode(rawOut, (bytes32[2]));
        assertEq(output[0], expected[0]);
        assertEq(output[1], expected[1]);
    }

    // function testPrecompileBlake2FWithoutScript() public {
    //     vm.pauseGasMetering();
    //     uint32 rounds = 12;

    //     bytes32[2] memory h;
    //     h[0] = hex"48c9bdf267e6096a3ba7ca8485ae67bb2bf894fe72f36e3cf1361d5f3af54fa5";
    //     h[1] = hex"d182e6ad7f520e511f6c3e2b8c68059b6bbd41fbabd9831f79217e1319cde05b";

    //     bytes32[4] memory m;
    //     m[0] = hex"6162630000000000000000000000000000000000000000000000000000000000";
    //     m[1] = hex"0000000000000000000000000000000000000000000000000000000000000000";
    //     m[2] = hex"0000000000000000000000000000000000000000000000000000000000000000";
    //     m[3] = hex"0000000000000000000000000000000000000000000000000000000000000000";

    //     bytes8[2] memory t;
    //     t[0] = hex"03000000";
    //     t[1] = hex"00000000";

    //     bool f = true;

    //     bytes32[2] memory expected;
    //     expected[0] = hex"ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d1";
    //     expected[1] = hex"7d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923";

    //     QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
    //         scriptAddress: address(0x9),
    //         scriptSource: "",
    //         scriptCalldata: abi.encodePacked(rounds, h[0], h[1], m[0], m[1], m[2], m[3], t[0], t[1], f),
    //         nonce: aliceWallet.stateManager().nextNonce(address(aliceWallet)),
    //         expiry: block.timestamp + 1000
    //     });
    //     (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
    //     vm.resumeGasMetering();
    //     bytes memory rawOut = aliceWallet.executeQuarkOperation(op, v, r, s);
    //     bytes32[2] memory output = abi.decode(rawOut, (bytes32[2]));
    //     assertEq(output[0], expected[0]);
    //     assertEq(output[1], expected[1]);
    // }

    function testRevertOnAllPrecompilesDirectCall() public {
        vm.pauseGasMetering();
        uint96 nonce = stateManager.nextNonce(address(aliceWallet));
        for (uint256 i = 1; i <= 9; i++) {
            vm.pauseGasMetering();
            QuarkWallet.QuarkOperation memory op = DummyQuarkOperation(address(uint160(i)), nonce++);
            (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
            vm.resumeGasMetering();
            vm.expectRevert(abi.encodeWithSelector(QuarkWallet.EmptyCode.selector));
            aliceWallet.executeQuarkOperation(op, v, r, s);
        }
    }

    function DummyQuarkOperation(address preCompileAddress, uint96 nonce)
        internal
        view
        returns (QuarkWallet.QuarkOperation memory)
    {
        return QuarkWallet.QuarkOperation({
            scriptAddress: preCompileAddress,
            scriptSource: "",
            scriptCalldata: hex"",
            nonce: nonce,
            expiry: block.timestamp + 1000
        });
    }
}
