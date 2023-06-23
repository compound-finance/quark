// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../lib/YulHelper.sol";
import "../lib/Counter.sol";

import "../../src/core_scripts/Ethcall.sol";
import "../../src/Relayer.sol";
import "../../src/RelayerKafka.sol";

contract EthcallTest is Test {
    Relayer public relayerKafka;
    Counter public counter;

    constructor() {
        relayerKafka = new RelayerKafka();
        console.log("Relayer kafka deployed to: %s", address(relayerKafka));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));
    }

    function setUp() public {
        // nothing
    }

    function testKafkaEthcallCounter() public {
        bytes memory ethcallScript = new YulHelper().getDeployed("Ethcall.sol/Ethcall.json");
        bytes memory ethcallInvocation = abi.encodeCall(Ethcall.run, (
            address(counter),
            abi.encodeCall(Counter.incrementBy, (20)),
            0
        ));

        assertEq(counter.number(), 0);

        bytes memory data = relayerKafka.runQuark(ethcallScript, ethcallInvocation);
        assertEq(data, hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000014");

        assertEq(counter.number(), 20);
    }
}
