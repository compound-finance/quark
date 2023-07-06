// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./lib/YulHelper.sol";
import "./lib/Counter.sol";
import "./lib/CounterScript.sol";
import "./lib/Invariant.sol";

import "../src/CodeJar.sol";
import "../src/Relayer.sol";
import "../src/RelayerAtomic.sol";

contract QuarkTest is Test {
    event Ping(uint256 value);

    Relayer public relayer;
    Counter public counter;
    CodeJar public codeJar;

    uint256 internal accountPrivateKey;
    uint256 internal searcherPrivateKey;

    address internal account;
    address internal searcher;

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        relayer = new RelayerAtomic(codeJar);
        console.log("Relayer deployed to: %s", address(relayer));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));
    }

    function setUp() public {
        // nothing
    }

    function testAtomicPing() public {
        bytes memory ping = new YulHelper().get("Ping.yul/Logger.json");

        // TODO: Check who emitted.
        vm.expectEmit(false, false, false, true);
        emit Ping(55);

        bytes memory data = relayer.runQuark(ping);
        assertEq(data, abi.encode());
    }

    function testAtomicIncrementer() public {
        bytes memory incrementer = new YulHelper().get("Incrementer.yul/Incrementer.json");

        assertEq(counter.number(), 0);

        vm.prank(address(0xaa));
        bytes memory data = relayer.runQuark(incrementer);
        assertEq(data, abi.encode());
        assertEq(counter.number(), 3);

        uint256 gl = gasleft();
        relayer.runQuark(incrementer);
        uint256 gasUsed = gl - gasleft();
        assertEq(counter.number(), 3);
        assertEq(gasUsed, 0);
    }

    function testAtomicGetOwner() public {
        bytes memory getOwner = new YulHelper().get("GetOwner.yul/GetOwner.json");

        vm.prank(address(0xaa));
        bytes memory data = relayer.runQuark(getOwner);
        assertEq(data, abi.encode(55));
    }

    function testAtomicCallback() public {
        bytes memory callback = new YulHelper().get("Callback.yul/Callback.json");

        assertEq(counter.number(), 0);

        vm.prank(address(0xaa));
        bytes memory data = relayer.runQuark(callback);
        assertEq(data, abi.encode());
        assertEq(counter.number(), 11);
    }

    function testAtomicNoCallbacks() public {
        bytes memory noCallback = new YulHelper().get("NoCallback.yul/Callback.json");

        assertEq(counter.number(), 0);

        vm.prank(address(0xaa));
        bytes memory data = relayer.runQuark(noCallback);
        assertEq(data, abi.encode());
        assertEq(counter.number(), 0);
    }

    function testAtomicCounterScript() public {
        bytes memory counterScript = new YulHelper().getDeployed("CounterScript.sol/CounterScript.json");

        assertEq(counter.number(), 0);

        vm.prank(address(0xaa));
        bytes memory data = relayer.runQuark(counterScript, abi.encodeCall(CounterScript.run, (counter)));
        assertEq(data, abi.encode());
        assertEq(counter.number(), 2);
    }

    function testAtomicCounterScriptWithInvariant() public {
        bytes memory counterScript = new YulHelper().getDeployed("CounterScript.sol/CounterScript.json");

        assertEq(counter.number(), 0);

        vm.prank(address(0xaa));
        relayer.setInvariant(type(CounterInvariant).runtimeCode, abi.encode(address(counter), 5), 0, address(0));

        vm.prank(address(0xaa));
        bytes memory data = relayer.runQuark(counterScript, abi.encodeCall(CounterScript.run, (counter)));
        assertEq(data, abi.encode(hex""));
        assertEq(counter.number(), 2);

        vm.prank(address(0xaa));
        relayer.runQuark(counterScript, abi.encodeCall(CounterScript.run, (counter)));
        assertEq(counter.number(), 4);

        vm.expectRevert(
            abi.encodeWithSelector(
                Relayer.InvariantFailed.selector,
                address(0xaa),
                relayer.invariants(address(0xaa)),
                abi.encode(address(counter), 5),
                abi.encodeWithSelector(CounterInvariant.CounterTooHigh.selector, 6, 5)
        ));

        vm.prank(address(0xaa));
        relayer.runQuark(counterScript, abi.encodeCall(CounterScript.run, (counter)));
        assertEq(counter.number(), 4);
    }

    function testAtomicDirectIncrementer() public {
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
