// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../lib/YulHelper.sol";
import "../lib/Counter.sol";

import "../../core_scripts/Ethcall.sol";
import "../../src/Relayer.sol";
import "../../src/RelayerMetamorphic.sol";
import "../../src/RelayerVm.sol";
import "../../src/RelayerKafka.sol";

contract EthcallTest is Test {
    Relayer public relayerMetamorphic;
    Relayer public relayerVm;
    Relayer public relayerKafka;
    Counter public counter;

    constructor() {
        relayerMetamorphic = new RelayerMetamorphic();
        console.log("Relayer metamorphic deployed to: %s", address(relayerMetamorphic));

        relayerVm = new RelayerVm();
        console.log("Relayer vm deployed to: %s", address(relayerVm));

        relayerKafka = new RelayerKafka();
        console.log("Relayer kafka deployed to: %s", address(relayerKafka));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));
    }

    function setUp() public {
        // nothing
    }

    function testMetamorphicEthcallCounter() public {
        bytes memory ethcallScript = new YulHelper().getDeployed("Ethcall.sol/Ethcall.json");
        Ethcall.EthcallInput memory input = Ethcall.EthcallInput({
            callContract: address(counter),
            callData: abi.encodeCall(Counter.incrementBy, (20)),
            callValue: 0
        });

        assertEq(counter.number(), 0);

        bytes memory data = relayerMetamorphic.runQuarkScript(ethcallScript, abi.encode(input));
        assertEq(data, hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000014");

        assertEq(counter.number(), 20);
    }

    function testVmEthcallCounter() public {
        bytes memory ethcallScript = new YulHelper().getDeployed("Ethcall.sol/Ethcall.json");
        Ethcall.EthcallInput memory input = Ethcall.EthcallInput({
            callContract: address(counter),
            callData: abi.encodeCall(Counter.incrementBy, (0xEE)),
            callValue: 0
        });

        assertEq(counter.number(), 0);

        bytes memory data = relayerVm.runQuarkScript(ethcallScript, abi.encode(input));
        assertEq(data, hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000014");

        assertEq(counter.number(), 0xEE);
    }

    function testKafkaEthcallCounter() public {
        bytes memory ethcallScript = new YulHelper().getDeployed("Ethcall.sol/Ethcall.json");
        Ethcall.EthcallInput memory input = Ethcall.EthcallInput({
            callContract: address(counter),
            callData: abi.encodeCall(Counter.incrementBy, (20)),
            callValue: 0
        });

        assertEq(counter.number(), 0);

        bytes memory data = relayerKafka.runQuarkScript(ethcallScript, abi.encode(input));
        assertEq(data, hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000014");

        assertEq(counter.number(), 20);
    }
}
