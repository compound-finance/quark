// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/CodeJar.sol";
import "../src/QuarkWallet.sol";

import "./lib/Counter.sol";
import "./lib/MaxCounterScript.sol";
import "./lib/YulHelper.sol";
import "./lib/Reverts.sol";

contract QuarkWalletTest is Test {
    event Ping(uint256);

    CodeJar public codeJar;
    Counter public counter;

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));
    }

    function testGetOwner() public {
        address account = address(0xaa);
        QuarkWallet wallet = new QuarkWallet{salt: 0}(account, codeJar);
        bytes memory result =
            wallet.executeQuarkOperation(new YulHelper().getDeployed("GetOwner.sol/GetOwner.json"), abi.encode());
        assertEq(result, abi.encode(0xaa));
    }

    function testQuarkOperationRevertsIfCodeNotFound() public {
        address account = address(0xaa);
        QuarkWallet wallet = new QuarkWallet{salt: 0}(account, codeJar);

        vm.expectRevert(abi.encodeWithSelector(QuarkWallet.QuarkCodeNotFound.selector));
        wallet.executeQuarkOperation(abi.encode(), abi.encodeWithSignature("x()"));
    }

    function testQuarkOperationRevertsIfCallReverts() public {
        address account = address(0xb0b);
        bytes memory revertsCode = new YulHelper().getDeployed("Reverts.sol/Reverts.json");
        QuarkWallet wallet = new QuarkWallet{salt: 0}(account, codeJar);
        vm.expectRevert(
            abi.encodeWithSelector(QuarkWallet.QuarkCallError.selector, abi.encodeWithSelector(Reverts.Whoops.selector))
        );
        wallet.executeQuarkOperation(revertsCode, abi.encode());
    }

    function testAtomicPing() public {
        bytes memory ping = new YulHelper().getDeployed("Logger.sol/Logger.json");
        // TODO: Check who emitted.
        address account = address(0xb0b);
        QuarkWallet wallet = new QuarkWallet{salt: 0}(account, codeJar);
        vm.expectEmit(false, false, false, true);
        emit Ping(55);
        wallet.executeQuarkOperation(ping, abi.encode());
    }

    function testAtomicIncrementer() public {
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");

        assertEq(counter.number(), 0);
        address account = address(0xb0b);
        QuarkWallet wallet = new QuarkWallet{salt: 0}(account, codeJar);
        wallet.executeQuarkOperation(incrementer, abi.encodeWithSignature("incrementCounter(address)", counter));
        assertEq(counter.number(), 3);
    }

    function testAtomicMaxCounterScript() public {
        bytes memory maxCounterScript = new YulHelper().getDeployed("MaxCounterScript.sol/MaxCounterScript.json");

        assertEq(counter.number(), 0);

        vm.startPrank(address(0xaa));

        address account = address(0xb0b);
        QuarkWallet wallet = new QuarkWallet{salt: 0}(account, codeJar);
        // call once
        wallet.executeQuarkOperation(maxCounterScript, abi.encodeCall(MaxCounterScript.run, (counter)));
        assertEq(counter.number(), 1);
        // call twice
        wallet.executeQuarkOperation(maxCounterScript, abi.encodeCall(MaxCounterScript.run, (counter)));
        // call thrice
        assertEq(counter.number(), 2);
        wallet.executeQuarkOperation(maxCounterScript, abi.encodeCall(MaxCounterScript.run, (counter)));
        assertEq(counter.number(), 3);

        // revert because max has been hit
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector, abi.encodeWithSelector(MaxCounterScript.EnoughAlready.selector)
            )
        );
        wallet.executeQuarkOperation(maxCounterScript, abi.encodeCall(MaxCounterScript.run, (counter)));
        assertEq(counter.number(), 3);

        vm.stopPrank();
    }
}
