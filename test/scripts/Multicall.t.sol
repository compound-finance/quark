// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../lib/YulHelper.sol";
import "../lib/Counter.sol";

import "../../src/scripts/Multicall.sol";
import "../../src/Relayer.sol";
import "../../src/RelayerMetamorphic.sol";

contract MulticallTest is Test {
    Relayer public relayer;
    Counter public counter;

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

    function testMulticallCounter() public {
        bytes memory multicallScript = new YulHelper().getDeployed("Multicall.sol/Multicall.json");
        address[] memory wrappedContracts = new address[](2);
        bytes[] memory wrappedCalldatas = new bytes[](2);
        wrappedContracts[0] = address(counter);
        wrappedContracts[1] = address(counter);
        wrappedCalldatas[0] = abi.encodeCall(Counter.incrementBy, (20));
        wrappedCalldatas[1] = abi.encodeCall(Counter.decrementBy, (5));
        Multicall.MulticallInput memory input = Multicall.MulticallInput({
            wrappedContracts: wrappedContracts,
            wrappedCalldatas: wrappedCalldatas
        });

        assertEq(counter.number(), 0);

        bytes memory data = relayer.runQuarkScript(multicallScript, abi.encode(input));
        assertEq(data, hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000014");

        assertEq(counter.number(), 15);
    }
}
