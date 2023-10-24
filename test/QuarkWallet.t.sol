// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/CodeJar.sol";
import "../src/QuarkWallet.sol";
import "../src/QuarkStorageManager.sol";

import "./lib/Counter.sol";
import "./lib/MaxCounterScript.sol";
import "./lib/Reverts.sol";

import "./lib/YulHelper.sol";
import "./lib/SignatureHelper.sol";

contract QuarkWalletTest is Test {
    event Ping(uint256);

    CodeJar public codeJar;
    Counter public counter;
    QuarkStorageManager public storageManager;

    uint256 alicePrivateKey = 0x8675309;
    address aliceAccount = vm.addr(alicePrivateKey);
    QuarkWallet aliceWallet; // see constructor()

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));

        storageManager = new QuarkStorageManager();
        console.log("QuarkStorageManager deployed to: %s", address(storageManager));

        aliceWallet = new QuarkWallet(aliceAccount, codeJar, storageManager);
        console.log("Alice wallet at: %s", address(aliceWallet));
    }

    function newBasicOp(QuarkWallet wallet, bytes memory scriptSource)
        internal
        returns (QuarkWallet.QuarkOperation memory)
    {
        return newBasicOp(wallet, scriptSource, abi.encode());
    }

    function newBasicOp(QuarkWallet wallet, bytes memory scriptSource, bytes memory scriptCalldata)
        internal
        returns (QuarkWallet.QuarkOperation memory)
    {
        return QuarkWallet.QuarkOperation({
            scriptSource: scriptSource,
            scriptCalldata: scriptCalldata,
            nonce: wallet.nextUnusedNonce(),
            expiry: block.timestamp + 1000,
            allowCallback: false
        });
    }

    function testGetOwner() public {
        bytes memory getOwner = new YulHelper().getDeployed("GetOwner.sol/GetOwner.json");
        QuarkWallet.QuarkOperation memory op = newBasicOp(aliceWallet, getOwner);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
        bytes memory result = aliceWallet.executeQuarkOperation(op, v, r, s);
        assertEq(result, abi.encode(aliceAccount));
    }

    function testQuarkOperationRevertsIfCodeNotFound() public {
        QuarkWallet.QuarkOperation memory op = newBasicOp(aliceWallet, abi.encode(), abi.encodeWithSignature("x()"));
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
        vm.expectRevert(abi.encodeWithSelector(QuarkWallet.QuarkCodeNotFound.selector));
        aliceWallet.executeQuarkOperation(op, v, r, s);
    }

    function testQuarkOperationRevertsIfCallReverts() public {
        bytes memory revertsCode = new YulHelper().getDeployed("Reverts.sol/Reverts.json");
        QuarkWallet.QuarkOperation memory op = newBasicOp(aliceWallet, revertsCode);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
        vm.expectRevert(
            abi.encodeWithSelector(QuarkWallet.QuarkCallError.selector, abi.encodeWithSelector(Reverts.Whoops.selector))
        );
        aliceWallet.executeQuarkOperation(op, v, r, s);
    }

    function testAtomicPing() public {
        bytes memory ping = new YulHelper().getDeployed("Logger.sol/Logger.json");
        QuarkWallet.QuarkOperation memory op = newBasicOp(aliceWallet, ping);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
        // TODO: Check who emitted.
        vm.expectEmit(false, false, false, true);
        emit Ping(55);
        aliceWallet.executeQuarkOperation(op, v, r, s);
    }

    function testAtomicIncrementer() public {
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");
        assertEq(counter.number(), 0);
        QuarkWallet.QuarkOperation memory op =
            newBasicOp(aliceWallet, incrementer, abi.encodeWithSignature("incrementCounter(address)", counter));
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
        aliceWallet.executeQuarkOperation(op, v, r, s);
        assertEq(counter.number(), 3);
    }

    function testAtomicMaxCounterScript() public {
        bytes memory maxCounterScript = new YulHelper().getDeployed("MaxCounterScript.sol/MaxCounterScript.json");
        assertEq(counter.number(), 0);

        vm.startPrank(address(aliceAccount));

        // call once
        {
            QuarkWallet.QuarkOperation memory op =
                newBasicOp(aliceWallet, maxCounterScript, abi.encodeCall(MaxCounterScript.run, (counter)));
            (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
            aliceWallet.executeQuarkOperation(op, v, r, s);
        }
        assertEq(counter.number(), 1);

        // call twice
        {
            QuarkWallet.QuarkOperation memory op =
                newBasicOp(aliceWallet, maxCounterScript, abi.encodeCall(MaxCounterScript.run, (counter)));
            (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
            aliceWallet.executeQuarkOperation(op, v, r, s);
        }
        assertEq(counter.number(), 2);

        // call thrice
        {
            QuarkWallet.QuarkOperation memory op =
                newBasicOp(aliceWallet, maxCounterScript, abi.encodeCall(MaxCounterScript.run, (counter)));
            (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
            aliceWallet.executeQuarkOperation(op, v, r, s);
        }
        assertEq(counter.number(), 3);

        // revert because max has been hit
        {
            QuarkWallet.QuarkOperation memory op =
                newBasicOp(aliceWallet, maxCounterScript, abi.encodeCall(MaxCounterScript.run, (counter)));
            (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
            vm.expectRevert(
                abi.encodeWithSelector(
                    QuarkWallet.QuarkCallError.selector, abi.encodeWithSelector(MaxCounterScript.EnoughAlready.selector)
                )
            );
            aliceWallet.executeQuarkOperation(op, v, r, s);
        }
        assertEq(counter.number(), 3);

        vm.stopPrank();
    }
}
