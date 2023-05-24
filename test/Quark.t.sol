// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./lib/YulHelper.sol";
import "forge-std/console.sol";

contract QuarkTest is Test {
    event Ping(uint256 value);

    address public quark;

    constructor() {
        quark = new YulHelper().deploy("Quark.yul/Quark.json");
        console.log("deployed to: %s", quark);
    }

    function setUp() public {
        // nothing
    }

    function testReflect() public {
        bytes memory reflect = new YulHelper().get("Reflect.yul/Reflect.json");
        console.logBytes(reflect);

        vm.breakpoint("a");

        // TODO: Check the emitter?
        vm.expectEmit(false, false, false, true);
        emit Ping(55);

        (bool success, bytes memory data) = quark.call(reflect);
        assertEq(success, true);
        assertEq(data, abi.encode());
    }
}
