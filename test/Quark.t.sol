// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./lib/YulHelper.sol";
import "../src/Counter.sol";

interface QuarkInterface {
    function quarkAddress25(address) external returns (address);
    function virtualCode81() external returns (bytes memory);
}

contract QuarkTest is Test {
    event Ping(uint256 value);

    address public quark;
    Counter public counter;

    constructor() {
        quark = new YulHelper().deploy("Quark.yul/Quark.json");
        console.log("Quark manager deployed to: %s", quark);

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));
    }

    function setUp() public {
        // nothing
    }

    function testLogger() public {
        bytes memory logger = new YulHelper().get("Logger.yul/Logger.json");
        console.logBytes(logger);

        // TODO: Check who emitted.
        vm.expectEmit(false, false, false, true);
        emit Ping(55);

        (bool success, bytes memory data) = quark.call(logger);
        assertEq(success, true);
        assertEq(data, abi.encode());
    }

    function testIncrementer() public {
        bytes memory incrementer = new YulHelper().get("Incrementer.yul/Incrementer.json");
        console.logBytes(incrementer);

        // assertEq(incrementer, QuarkInterface(quark).virtualCode81());
        // assertEq(address(0x6c022704D948c71930B35B6F6bb725bc8d687E7F), QuarkInterface(quark).quarkAddress25(address(1)));

        assertEq(counter.number(), 0);

        vm.prank(address(0x88));
        (bool success0, bytes memory data0) = quark.call(incrementer);
        assertEq(success0, true);
        assertEq(data0, abi.encode());
        assertEq(counter.number(), 1);
    }
}
