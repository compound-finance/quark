// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./lib/YulHelper.sol";
import "./lib/Counter.sol";

import "../src/Relayer.sol";
import "../src/RelayerMetamorphic.sol";

contract QuarkTest is Test {
    event Ping(uint256 value);

    Relayer public relayer;
    Counter public counter;

    uint256 internal accountPrivateKey;
    uint256 internal searcherPrivateKey;

    address internal account;
    address internal searcher;

    constructor() {
        relayer = new RelayerMetamorphic();
        console.log("Relayer deployed to: %s", address(relayer));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));
    }

    function setUp() public {
        // nothing
    }

    function testMetamorphicPing() public {
        bytes memory ping = new YulHelper().get("Ping.yul/Logger.json");

        // TODO: Check who emitted.
        vm.expectEmit(false, false, false, true);
        emit Ping(55);

        bytes memory data = relayer.runQuark(ping);
        assertEq(data, abi.encode());
    }

    function testMetamorphicIncrementer() public {
        bytes memory incrementer = new YulHelper().get("Incrementer.yul/Incrementer.json");

        assertEq(counter.number(), 0);

        vm.prank(address(0xaa));
        bytes memory data = relayer.runQuark(incrementer);
        assertEq(data, abi.encode());
        assertEq(counter.number(), 3);
    }

    function testMetamorphicCallback() public {
        bytes memory callback = new YulHelper().get("Callback.yul/Callback.json");

        assertEq(counter.number(), 0);

        vm.prank(address(0xaa));
        bytes memory data = relayer.runQuark(callback);
        assertEq(data, abi.encode());
        assertEq(counter.number(), 11);
    }

    function testMetamorphicNoCallbacks() public {
        bytes memory noCallback = new YulHelper().get("NoCallback.yul/Callback.json");

        assertEq(counter.number(), 0);

        vm.prank(address(0xaa));
        bytes memory data = relayer.runQuark(noCallback);
        assertEq(data, abi.encode());
        assertEq(counter.number(), 0);
    }

    function testMetamorphicCounterScript() public {
        bytes memory counterScript = new YulHelper().getDeployed("CounterScript.sol/CounterScript.json");

        assertEq(counter.number(), 0);

        vm.prank(address(0xaa));
        bytes memory data = relayer.runQuarkScript(counterScript, abi.encode(counter));
        assertEq(data, abi.encode());
        assertEq(counter.number(), 2);
    }

    function testMetamorphicDirectIncrementer() public {
        bytes memory incrementer = new YulHelper().get("Incrementer.yul/Incrementer.json");

        // assertEq(incrementer, QuarkInterface(quark).virtualCode81());
        // assertEq(address(0x6c022704D948c71930B35B6F6bb725bc8d687E7F), QuarkInterface(quark).quarkAddress25(address(1)));

        assertEq(counter.number(), 0);

        vm.prank(address(0xaa));
        (bool success0, bytes memory data0) = address(relayer).call(incrementer);
        assertEq(success0, true);
        assertEq(data0, abi.encode());
        assertEq(counter.number(), 3);
    }
}