// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./lib/YulHelper.sol";
import "./lib/Counter.sol";
import "./lib/VmTest.sol";

import "../src/QuarkVm.sol";

interface Error {
    function StackUnderflow() external;
    function StackOverflow() external;
    function PushOutOfBound() external;
}

contract QuarkVmTest is Test {
    QuarkVm quarkVm;
    Counter public counter;

    constructor() {
        quarkVm = new QuarkVm();
        console.log("Quark Vm deployed to: %s", address(quarkVm));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));
    }

    function setUp() public {
        // nothing
    }

    function testVm_Add() public {
        (bytes memory res, bytes memory err) = new VmTest().runYul(VmTest.YulTestCase({
            yul: ""
                "let a := 0x55 \n"
                "let b := 0x22 \n"
                "mstore(0x00, add(a, b)) \n"
                "return(0x00, 0x20) \n"
            "",
            data: hex""
        }));
        assertEq(0x77, abi.decode(res, (uint256)));
        assertEq(hex"", err);
    }

    function testVm_Sub() public {
        (bytes memory res, bytes memory err) = new VmTest().runYul(VmTest.YulTestCase({
            yul: ""
                "let a := 0x55 \n"
                "let b := 0x22 \n"
                "mstore(0x00, sub(a, b)) \n"
                "return(0x00, 0x20) \n"
            "",
            data: hex""
        }));
        assertEq(0x33, abi.decode(res, (uint256)));
        assertEq(hex"", err);
    }

    function testVm_Calldataload_0() public {
        (bytes memory res, bytes memory err) = new VmTest().runYul(VmTest.YulTestCase({
            yul: ""
                "mstore(0x00, calldataload(0)) \n"
                "return(0x00, 0x20) \n"
            "",
            data: hex"1234567812345678123456781234567812345678123456781234567812345678"
        }));
        assertEq(hex"1234567812345678123456781234567812345678123456781234567812345678", res);
        assertEq(hex"", err);
    }

    function testVm_Calldataload_Partial() public {
        (bytes memory res, bytes memory err) = new VmTest().runYul(VmTest.YulTestCase({
            yul: ""
                "mstore(0x00, calldataload(0x02)) \n"
                "return(0x00, 0x20) \n"
            "",
            data: hex"1234567812345678123456781234567812345678123456781234567812345678"
        }));
        assertEq(hex"5678123456781234567812345678123456781234567812345678123456780000", res);
        assertEq(hex"", err);
    }

    function testVm_Calldataload_PartialSpan() public {
        (bytes memory res, bytes memory err) = new VmTest().runYul(VmTest.YulTestCase({
            yul: ""
                "mstore(0x00, calldataload(0x02)) \n"
                "return(0x00, 0x20) \n"
            "",
            data: hex"1234567812345678123456781234567812345678123456781234567812345678aabbccddeeffaabbccddeeffaabbccddeeff"
        }));
        assertEq(hex"567812345678123456781234567812345678123456781234567812345678aabb", res);
        assertEq(hex"", err);
    }

    function testVm_Calldataload_Deadspace() public {
        (bytes memory res, bytes memory err) = new VmTest().runYul(VmTest.YulTestCase({
            yul: ""
                "mstore(0x00, calldataload(0x60)) \n"
                "return(0x00, 0x20) \n"
            "",
            data: hex"1234567812345678123456781234567812345678123456781234567812345678aabbccddeeffaabbccddeeffaabbccddeeff"
        }));
        assertEq(hex"0000000000000000000000000000000000000000000000000000000000000000", res);
        assertEq(hex"", err);
    }

    function testVm_Calldatasize_Empty() public {
        (bytes memory res, bytes memory err) = new VmTest().runYul(VmTest.YulTestCase({
            yul: ""
                "mstore(0x00, calldatasize()) \n"
                "return(0x00, 0x20) \n"
            "",
            data: hex""
        }));
        assertEq(0x0, abi.decode(res, (uint256)));
        assertEq(hex"", err);
    }

    function testVm_Calldatasize_Filled() public {
        (bytes memory res, bytes memory err) = new VmTest().runYul(VmTest.YulTestCase({
            yul: ""
                "mstore(0x00, calldatasize()) \n"
                "return(0x00, 0x20) \n"
            "",
            data: hex"1234567812345678123456781234567812345678123456781234567812345678aabbccddeeffaabbccddeeffaabbccddeeff"
        }));
        assertEq(50, abi.decode(res, (uint256)));
        assertEq(hex"", err);
    }

    function testVm_Calldatacopy_Start_Filled() public {
        (bytes memory res, bytes memory err) = new VmTest().runYul(VmTest.YulTestCase({
            yul: ""
                "calldatacopy(0x100, 0x00, 0x24) \n"
                "return(0x100, 0x24) \n"
            "",
            data: hex"1234567812345678123456781234567812345678123456781234567812345678aabbccddeeffaabbccddeeffaabbccddeeff"
        }));
        assertEq(hex"1234567812345678123456781234567812345678123456781234567812345678aabbccdd", res);
        assertEq(hex"", err);
    }

    function testVm_Calldatacopy_Mid_Excess() public {
        (bytes memory res, bytes memory err) = new VmTest().runYul(VmTest.YulTestCase({
            yul: ""
                "mstore(0x100, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff) \n"
                "mstore(0x120, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff) \n"
                "calldatacopy(0x100, 0x1e, 0x24) \n"
                "return(0x100, 0x24) \n"
            "",
            data: hex"1234567812345678123456781234567812345678123456781234567812345678aabbccddeeffaabbccddeeffaabbccddeeff"
        }));
        assertEq(hex"5678aabbccddeeffaabbccddeeffaabbccddeeff00000000000000000000000000000000", res);
        assertEq(hex"", err);
    }

    function testVm_Calldatacopy_Deadspace() public {
        (bytes memory res, bytes memory err) = new VmTest().runYul(VmTest.YulTestCase({
            yul: ""
                "mstore(0x100, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff) \n"
                "mstore(0x120, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff) \n"
                "calldatacopy(0x100, 0x100, 0x24) \n"
                "return(0x100, 0x24) \n"
            "",
            data: hex"1234567812345678123456781234567812345678123456781234567812345678aabbccddeeffaabbccddeeffaabbccddeeff"
        }));
        assertEq(hex"000000000000000000000000000000000000000000000000000000000000000000000000", res);
        assertEq(hex"", err);
    }

    function testVm_Calldatacopy_DeadspaceBoundary() public {
        (bytes memory res, bytes memory err) = new VmTest().runYul(VmTest.YulTestCase({
            yul: ""
                "mstore(0x100, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff) \n"
                "mstore(0x120, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff) \n"
                "calldatacopy(0x100, 50, 0x24) \n"
                "return(0x100, 0x24) \n"
            "",
            data: hex"1234567812345678123456781234567812345678123456781234567812345678aabbccddeeffaabbccddeeffaabbccddeeff"
        }));
        assertEq(hex"000000000000000000000000000000000000000000000000000000000000000000000000", res);
        assertEq(hex"", err);
    }

    function testVm_StackOkay() public {
        (bytes memory res, bytes memory err) = new VmTest().runAsm(VmTest.AsmTestCase({
            asm: "PUSH0;PUSH0;POP;POP;PUSH0;PUSH0;RETURN",
            data: hex""
        }));
        assertEq(hex"", res);
        assertEq(hex"", err);
    }

    function testVm_StackUnderflow() public {
        (bytes memory res, bytes memory err) = new VmTest().runAsm(VmTest.AsmTestCase({
            asm: "PUSH0;PUSH0;POP;POP;POP;PUSH0;PUSH0;RETURN",
            data: hex""
        }));
        assertEq(res, hex"");
        assertEq(err, abi.encodeCall(Error.StackUnderflow, ()));
    }

    function testVm_StackOkay_Dup2() public {
        (bytes memory res, bytes memory err) = new VmTest().runAsm(VmTest.AsmTestCase({
            asm: "PUSH1 0x55;PUSH0;DUP2;PUSH0;MSTORE;PUSH1 0x20;PUSH0;RETURN",
            data: hex""
        }));
        assertEq(res, hex"0000000000000000000000000000000000000000000000000000000000000055");
        assertEq(err, hex"");
    }

    function testVm_StackOkay_Swap1() public {
        (bytes memory res, bytes memory err) = new VmTest().runAsm(VmTest.AsmTestCase({
            asm: "PUSH1 0x55;PUSH0;SWAP1;PUSH0;MSTORE;PUSH1 0x20;PUSH0;RETURN",
            data: hex""
        }));
        assertEq(res, hex"0000000000000000000000000000000000000000000000000000000000000055");
        assertEq(err, hex"");
    }

    function testVm_StackUnderflow_Dup2() public {
        (bytes memory res, bytes memory err) = new VmTest().runAsm(VmTest.AsmTestCase({
            asm: "PUSH0;DUP2",
            data: hex""
        }));
        assertEq(res, hex"");
        assertEq(err, abi.encodeCall(Error.StackUnderflow, ()));
    }

    function testVm_StackUnderflow_Swap1() public {
        (bytes memory res, bytes memory err) = new VmTest().runAsm(VmTest.AsmTestCase({
            asm: "PUSH0;SWAP1",
            data: hex""
        }));
        assertEq(res, hex"");
        assertEq(err, abi.encodeCall(Error.StackUnderflow, ()));
    }

    function testVm_StackOverflow_Almost() public {
        (bytes memory res, bytes memory err) = new VmTest().runAsm(VmTest.AsmTestCase({
            asm: "PUSH2 1020; PUSH0; MSTORE;" // mstore(0, 1020)
                "JUMPDEST;"
                "PUSH0;" // push0 [incr stack depth]
                "PUSH0; MLOAD;" // mload(0)
                "PUSH1 1;"
                "SWAP1;"
                "SUB;"
                "DUP1;" // dup
                "PUSH0;"
                "MSTORE;" // mstore(0, sub(mload(0), 1))
                "PUSH0;"
                "SWAP1;"
                "GT;"
                "PUSH1 5;" // JUMPDEST
                "JUMPI;"
                "PUSH0; PUSH0; RETURN;",
            data: hex""
        }));
        assertEq(res, hex"");
        assertEq(err, hex"");
    }

    function testVm_StackOverflow_ViaPush() public {
        (bytes memory res, bytes memory err) = new VmTest().runAsm(VmTest.AsmTestCase({
            asm: "PUSH2 1020; PUSH0; MSTORE;" // mstore(0, 1020)
                "JUMPDEST;"
                "PUSH0;" // push0 [incr stack depth]
                "PUSH0; MLOAD;" // mload(0)
                "PUSH1 1;"
                "SWAP1;"
                "SUB;"
                "DUP1;" // dup
                "PUSH0;"
                "MSTORE;" // mstore(0, sub(mload(0), 1))
                "PUSH0;"
                "SWAP1;"
                "GT;"
                "PUSH1 5;" // JUMPDEST
                "JUMPI;"
                "PUSH0; PUSH0; PUSH0; PUSH0; RETURN;",
            data: hex""
        }));
        assertEq(res, hex"");
        assertEq(err, abi.encodeCall(Error.StackOverflow, ()));
    }

    function testVm_PushOutOfBounds() public {
        (bytes memory res, bytes memory err) = new VmTest().runAsmBin(VmTest.AsmBinTestCase({
            asm: hex"601166112233445566",
            data: hex""
        }));
        assertEq(res, hex"");
        assertEq(err, abi.encodeCall(Error.PushOutOfBound, ()));
    }

    // function testVmSimple() public {
    //     (bool success, bytes memory res) = address(quarkVm).call(new YulHelper().get("VmTest.yul/Simple.json"));
    //     assertEq(success, true);
    //     assertEq(res, hex"");
    // }

    // function testVmCounter() public {
    //     bytes memory incrementer = new YulHelper().get("Incrementer.yul/Incrementer.json");

    //     QuarkVm.VmCall memory vmCall = QuarkVm.VmCall({
    //         vmCode: incrementer,
    //         vmCalldata: hex""
    //     });

    //     assertEq(counter.number(), 0);

    //     vm.prank(address(0xaa));
    //     bytes memory res = quarkVm.runYul(vmCall);
    //     assertEq(res, abi.encode());
    //     assertEq(counter.number(), 33);
    // }

}
