// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ERC20Mock } from "openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../lib/YulHelper.sol";
import "../lib/Counter.sol";
import "../lib/MockPool.sol";

import "../../src/scripts/FlashMulticall.sol";
import "../../src/Relayer.sol";
import "../../src/RelayerMetamorphic.sol";

contract FlashMulticallTest is Test {
    Relayer public relayer;
    Counter public counter;
    ERC20Mock public token0;
    ERC20Mock public token1;
    MockPool public pool;

    constructor() {
        relayer = new RelayerMetamorphic();
        console.log("Relayer deployed to: %s", address(relayer));

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

    function testFlashMulticallCounter() public {
        bytes memory flashMulticallScript = new YulHelper().getDeployed("FlashMulticall.sol/FlashMulticall.json");
        address[] memory wrappedContracts = new address[](3);
        bytes[] memory wrappedCalldatas = new bytes[](3);
        address quarkAddress = relayer.getQuarkAddress(address(0xaa));
        wrappedContracts[0] = address(counter);
        wrappedContracts[1] = address(counter);
        wrappedContracts[2] = address(token0);
        wrappedCalldatas[0] = abi.encodeCall(Counter.incrementBy, (20));
        wrappedCalldatas[1] = abi.encodeCall(Counter.decrementBy, (5));
        wrappedCalldatas[2] = abi.encodeCall(ERC20Mock.mint, (quarkAddress, 0.005e18));
        FlashMulticall.FlashMulticallInput memory input = FlashMulticall.FlashMulticallInput({
            pool: address(pool),
            amount0: 1e18, // take one token of token1
            amount1: 0e18,
            wrappedContracts: wrappedContracts,
            wrappedCalldatas: wrappedCalldatas
        });
        assertEq(abi.encode(input), hex"");

        assertEq(counter.number(), 0);

        // TODO: This should fail since we don't / can't repay the flash loan yet
        vm.prank(address(0xaa));
        bytes memory data = relayer.runQuarkScript(flashMulticallScript, abi.encode(input));
        assertEq(data, hex"0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000");

        assertEq(counter.number(), 15);
        assertEq(token0.balanceOf(quarkAddress), 0.002e18);
    }
}
