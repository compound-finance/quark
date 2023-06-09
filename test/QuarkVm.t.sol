// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./lib/YulHelper.sol";
import "./lib/Counter.sol";

contract QuarkVmTest is Test {
    address quarkVm;
    Counter public counter;        

    constructor() {
        quarkVm = new YulHelper().deploy("QuarkVm.yul/QuarkVm.json");
        console.log("Quark Vm deployed to: %s", address(quarkVm));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));
    }

    function setUp() public {
        // nothing
    }

    function testVmManual() public {
        (bool success, bytes memory res) = quarkVm.call{value: 0x55}(hex"6112346005025f5fa1");
        assertEq(success, true);
        assertEq(res, hex"");
    }

    function testVmSimple() public {
        (bool success, bytes memory res) = quarkVm.call(new YulHelper().get("VmTest.yul/Simple.json"));
        assertEq(success, true);
        assertEq(res, hex"");
    }

    function testVmCounter() public {
        bytes memory incrementer = new YulHelper().get("Incrementer.yul/Incrementer.json");

        assertEq(counter.number(), 0);

        vm.prank(address(0xaa));
        (bool success, bytes memory res) = quarkVm.call(incrementer);
        assertEq(success, true);
        assertEq(res, abi.encode());
        assertEq(counter.number(), 33);
    }

}
