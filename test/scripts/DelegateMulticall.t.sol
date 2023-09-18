// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../lib/YulHelper.sol";
import "../lib/Counter.sol";

import "../../src/core_scripts/DelegateMulticall.sol";
import "../../src/CodeJar.sol";
import "../../src/Relayer.sol";
import "../../src/RelayerAtomic.sol";

contract RunThrice is QuarkScript {
    error EnoughAlready(uint256 max);

    string constant countVar = "quark.org.RunThrice.count";

    function runCheck(uint256 max) external {
        uint256 count = sloadU256(countVar);
        if (count >= max) {
          revert EnoughAlready(max);
        }

        sstoreU256(countVar, count + 1);
    }
}

contract DelegateMulticallTest is Test {
    Relayer public relayerAtomic;
    Counter public counter;
    CodeJar public codeJar;

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        relayerAtomic = new RelayerAtomic(codeJar);
        console.log("Relayer kafka deployed to: %s", address(relayerAtomic));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));
    }

    function setUp() public {
        // nothing
    }

    function testAtomicDelegateMulticallCounter() public {
        bytes memory multicallScript = new YulHelper().getDeployed("DelegateMulticall.sol/DelegateMulticall.json");
        address[] memory callContracts = new address[](2);
        bytes[] memory callCodes = new bytes[](2);
        bytes[] memory callDatas = new bytes[](2);
        uint256[] memory callValues = new uint256[](2);
        callContracts[0] = address(0);
        callCodes[0] = type(RunThrice).runtimeCode;
        callDatas[0] = abi.encodeCall(RunThrice.runCheck, (3));
        callValues[0] = 0 wei;
        callContracts[1] = address(counter);
        callCodes[1] = hex"";
        callDatas[1] = abi.encodeCall(Counter.incrementBy, (20));
        callValues[1] = 0 wei;
        bytes memory multicallInvocation = abi.encodeCall(DelegateMulticall.run, (
            callContracts,
            callCodes,
            callDatas,
            callValues
        ));

        assertEq(counter.number(), 0);

        vm.prank(address(0xaa));
        relayerAtomic.runQuark(multicallScript, multicallInvocation);
        assertEq(counter.number(), 20);

        vm.prank(address(0xaa));
        relayerAtomic.runQuark(multicallScript, multicallInvocation);
        assertEq(counter.number(), 40);

        vm.prank(address(0xaa));
        relayerAtomic.runQuark(multicallScript, multicallInvocation);
        assertEq(counter.number(), 60);

        vm.expectRevert(
            abi.encodeWithSelector(
                RelayerAtomic.QuarkCallFailed.selector,
                relayerAtomic.getQuarkAddress(address(0xaa)),
                abi.encodeWithSelector(DelegateMulticall.DelegateCallError.selector, 0, callCodes[0], callDatas[0], callValues[0],
                    abi.encodeWithSelector(RunThrice.EnoughAlready.selector, 3)
                )
        ));

        vm.prank(address(0xaa));
        relayerAtomic.runQuark(multicallScript, multicallInvocation);
        assertEq(counter.number(), 60);
    }
}
