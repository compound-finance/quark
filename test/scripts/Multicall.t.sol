// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../lib/YulHelper.sol";
import "../lib/Counter.sol";

import "../../core_scripts/Multicall.sol";
import "../../src/Relayer.sol";
import "../../src/RelayerMetamorphic.sol";
import "../../src/RelayerKafka.sol";

contract MulticallTest is Test {
    Relayer public relayerMetamorphic;
    Relayer public relayerKafka;
    Counter public counter;

    constructor() {
        relayerMetamorphic = new RelayerMetamorphic();
        console.log("Relayer metamorphic deployed to: %s", address(relayerMetamorphic));

        relayerKafka = new RelayerKafka();
        console.log("Relayer kafka deployed to: %s", address(relayerKafka));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));
    }

    function setUp() public {
        // nothing
    }

    function testMetamorphicMulticallCounter() public {
        bytes memory multicallScript = new YulHelper().getDeployed("Multicall.sol/Multicall.json");
        address[] memory callContracts = new address[](2);
        bytes[] memory callDatas = new bytes[](2);
        uint256[] memory callValues = new uint256[](2);
        callContracts[0] = address(counter);
        callDatas[0] = abi.encodeCall(Counter.incrementBy, (20));
        callValues[0] = 0 wei;
        callContracts[1] = address(counter);
        callDatas[1] = abi.encodeCall(Counter.decrementBy, (5));
        callValues[1] = 0 wei;
        Multicall.MulticallInput memory input = Multicall.MulticallInput({
            callContracts: callContracts,
            callDatas: callDatas,
            callValues: callValues
        });

        assertEq(counter.number(), 0);

        bytes memory data = relayerMetamorphic.runQuarkScript(multicallScript, abi.encode(input));
        assertEq(data, hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000014");

        assertEq(counter.number(), 15);
    }

    function testKafkaMulticallCounter() public {
        bytes memory multicallScript = new YulHelper().getDeployed("Multicall.sol/Multicall.json");
        address[] memory callContracts = new address[](2);
        bytes[] memory callDatas = new bytes[](2);
        uint256[] memory callValues = new uint256[](2);
        callContracts[0] = address(counter);
        callDatas[0] = abi.encodeCall(Counter.incrementBy, (20));
        callValues[0] = 0 wei;
        callDatas[1] = abi.encodeCall(Counter.decrementBy, (5));
        callContracts[1] = address(counter);
        callValues[1] = 0 wei;
        Multicall.MulticallInput memory input = Multicall.MulticallInput({
            callContracts: callContracts,
            callDatas: callDatas,
            callValues: callValues
        });

        assertEq(counter.number(), 0);

        bytes memory data = relayerKafka.runQuarkScript(multicallScript, abi.encode(input));

        assertEq(counter.number(), 15);
    }
}
