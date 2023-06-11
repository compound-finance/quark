// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import "../../src/QuarkVm.sol";

contract VmTest is Test {
    struct YulTestCase {
        string yul;
        bytes data;
    }

    function tryRunQuark(QuarkVm.VmCall memory vmCall) internal returns (bytes memory, bytes memory) {
        try new QuarkVm().run(vmCall) {
            uint256 retSize;
            assembly {
                retSize := returndatasize()
            }
            bytes memory returnData = new bytes(retSize);
            assembly {
                returndatacopy(add(returnData, 0x20), 0, retSize)
            }
            return (returnData, hex"");
        } catch (bytes memory err) {
            return (hex"", err);
        }
    }

    function runYul(YulTestCase calldata testCase) external returns (bytes memory, bytes memory) {
        string[] memory inputs = new string[](2);
        inputs[0] = "script/compile_yul.sh";
        inputs[1] = testCase.yul;

        bytes memory quarkCode = vm.ffi(inputs);

        QuarkVm.VmCall memory vmCall = QuarkVm.VmCall({
            vmCode: quarkCode,
            vmCalldata: testCase.data
        });

        vm.prank(address(0xaa));
        return tryRunQuark(vmCall);
    }

    struct AsmTestCase {
        string asm;
        bytes data;
    }

    function runAsm(AsmTestCase calldata testCase) external returns (bytes memory, bytes memory) {
        string[] memory inputs = new string[](3);
        inputs[0] = "node";
        inputs[1] = "script/assembler.js";
        inputs[2] = testCase.asm;

        bytes memory quarkCode = vm.ffi(inputs);

        QuarkVm.VmCall memory vmCall = QuarkVm.VmCall({
            vmCode: quarkCode,
            vmCalldata: testCase.data
        });

        vm.prank(address(0xaa));
        return tryRunQuark(vmCall);
    }

    struct AsmBinTestCase {
        bytes asm;
        bytes data;
    }

    function runAsmBin(AsmBinTestCase calldata testCase) external returns (bytes memory, bytes memory) {
        QuarkVm.VmCall memory vmCall = QuarkVm.VmCall({
            vmCode: testCase.asm,
            vmCalldata: testCase.data
        });

        vm.prank(address(0xaa));
        return tryRunQuark(vmCall);
    }
}
