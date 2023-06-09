// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../lib/YulHelper.sol";
import "../lib/Counter.sol";

import "../../src/scripts/Ethcall.sol";
import "../../src/Relayer.sol";
import "../../src/RelayerMetamorphic.sol";

contract EthcallTest is Test {
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

    function testEthcallCounter() public {
        bytes memory ethcallScript = new YulHelper().getDeployed("Ethcall.sol/Ethcall.json");
        Ethcall.EthcallInput memory input = Ethcall.EthcallInput({
            wrappedContract: address(counter),
            wrappedCalldata: abi.encodeCall(Counter.incrementBy, (20))
        });

        assertEq(counter.number(), 0);

        bytes memory data = relayer.runQuarkScript(ethcallScript, abi.encode(input));
        assertEq(data, hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000014");

        assertEq(counter.number(), 20);
    }
}
