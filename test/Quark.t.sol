// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./lib/JsonDeployer.sol";

contract ExampleTest is Test {
    address public adder;

    constructor() {
        adder = new JsonDeployer().deploy("Quark.yul/Quark.json");
        console.log("deployed to: %s", adder);
    }

    function setUp() public {
        // nothing
    }

    function testADDRESS() public {
        bytes memory testFn = new bytes(1);
        testFn[0] = 0x30; // ADDRESS
        (bool success, bytes memory data) = adder.call(testFn);
        assertEq(success, true);
        assertEq(data, abi.encode(2));
    }
}
