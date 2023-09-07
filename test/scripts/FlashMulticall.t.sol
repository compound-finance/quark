// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ERC20Mock } from "openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../lib/YulHelper.sol";
import "../lib/Counter.sol";
import "../lib/MockPool.sol";

import "../../src/core_scripts/FlashMulticall.sol";
import "../../src/CodeJar.sol";
import "../../src/Relayer.sol";
import "../../src/RelayerKafka.sol";

contract FlashMulticallTest is Test {
    Relayer public relayerKafka;
    Counter public counter;
    ERC20Mock public token0;
    ERC20Mock public token1;
    MockPool public pool;
    CodeJar public codeJar;

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        relayerKafka = new RelayerKafka(codeJar);
        console.log("Relayer kafka deployed to: %s", address(relayerKafka));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));

        token0 = new ERC20Mock();
        console.log("Token0 deployed to: %s", address(token0));

        token1 = new ERC20Mock();
        console.log("Token1 deployed to: %s", address(token1));

        pool = new MockPool(address(token0), address(token1), 30);
        console.log("Pool deployed to: %s", address(pool));

        token0.mint(address(pool), 100e18); // give the pool tokens
        token1.mint(address(pool), 50e18); // give the pool tokens
    }

    function setUp() public {
        // nothing
    }

    function testKafkaFlashMulticallCounter() public {
        bytes memory flashMulticallScript = new YulHelper().getDeployed("FlashMulticall.sol/FlashMulticall.json");
        address[] memory callContracts = new address[](3);
        bytes[] memory callDatas = new bytes[](3);
        uint256[] memory callValues = new uint256[](2);
        address quarkAddress = relayerKafka.getQuarkAddress(address(0xaa));
        callContracts[0] = address(counter);
        callDatas[0] = abi.encodeCall(Counter.incrementBy, (20));
        callValues[0] = 0 wei;
        callContracts[1] = address(counter);
        callDatas[1] = abi.encodeCall(Counter.decrementBy, (5));
        callValues[1] = 0 wei;
        callContracts[2] = address(token0);
        callDatas[2] = abi.encodeCall(ERC20Mock.mint, (quarkAddress, 0.005e18));
        callValues[2] = 0 wei;
        bytes memory flashMulticallInvocation = abi.encodeCall(FlashMulticall.run, (
            address(pool),
            1e18, // take one token of token1
            0e18,
            callContracts,
            callDatas,
            callValues
        ));

        assertEq(counter.number(), 0);

        // TODO: This should fail since we don't / can't repay the flash loan yet
        vm.prank(address(0xaa));
        bytes memory data = relayerKafka.runQuark(flashMulticallScript, flashMulticallInvocation);
        // assertEq(data, hex"0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000");

        assertEq(counter.number(), 15);
        assertEq(token0.balanceOf(quarkAddress), 0.002e18);
    }
}
