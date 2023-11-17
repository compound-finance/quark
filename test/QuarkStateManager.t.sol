// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/CodeJar.sol";
import "../src/QuarkWallet.sol";

import "./lib/YulHelper.sol";
import "./lib/SignatureHelper.sol";
import "./lib/QuarkOperationHelper.sol";
import "./lib/QuarkStateManagerHarness.sol";

contract QuarkStateManagerTest is Test {
    CodeJar public codeJar;
    QuarkStateManagerHarness public stateManager;

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        stateManager = new QuarkStateManagerHarness();
        console.log("QuarkStateManagerHarness deployed to: %s", address(stateManager));
    }

    function testRevertsForNoActiveNonce() public {
        // this contract does not have an active nonce
        vm.expectRevert(abi.encodeWithSelector(QuarkStateManager.NoNonceActive.selector));
        stateManager.clearNonce();

        vm.expectRevert(abi.encodeWithSelector(QuarkStateManager.NoNonceActive.selector));
        stateManager.read(bytes32("hello"));

        vm.expectRevert(abi.encodeWithSelector(QuarkStateManager.NoNonceActive.selector));
        stateManager.write(bytes32("hello"), bytes32("goodbye"));

        vm.expectRevert(abi.encodeWithSelector(QuarkStateManager.NoNonceActive.selector));
        stateManager.getActiveScript();
    }

    function testNonceZeroIsValid() public {
        // by default, nonce 0 is not set
        assertEq(stateManager.isNonceSet(address(0x123), 0), false);

        // nonce 0 can be set manually
        vm.prank(address(0x123));
        stateManager.setNonce(0);
        assertEq(stateManager.isNonceSet(address(0x123), 0), true);

        // a QuarkWallet can use nonce 0 as the active nonce
        vm.pauseGasMetering(); // do not meter deployment gas
        QuarkWallet wallet = new QuarkWallet(address(0), address(0), codeJar, stateManager);
        bytes memory getMessageDetails = new YulHelper().getDeployed("GetMessageDetails.sol/GetMessageDetails.json");
        address scriptAddress = codeJar.saveCode(getMessageDetails);
        bytes memory call = abi.encodeWithSignature("getMsgSenderAndValue()");
        vm.resumeGasMetering();

        vm.prank(address(wallet));
        bytes memory result = stateManager.setActiveNonceAndCallback(0, scriptAddress, call);
        assertEq(result, abi.encode(address(wallet), 0));
        assertEq(stateManager.isNonceSet(address(wallet), 0), true);
        // TODO: enable this test-case once nonceScriptAddress is public
        // assertEq(stateManager.nonceScriptAddress(address(wallet), 0), scriptAddress);
    }

    function testSetActiveNonceAndCallbackNotImplemented() public {
        // address(this) is a contract that does not implement a fallback; should revert
        vm.expectRevert();
        stateManager.setActiveNonceAndCallback(0, address(0), bytes(""));

        // for an EOA, setActiveNonceAndCallback will also revert...
        vm.expectRevert();
        vm.prank(address(0x123));
        stateManager.setActiveNonceAndCallback(0, address(0x123), bytes(""));
    }

    function testScriptAddressIsNull() public {
        // the null script is not special: since it can never run any code, it just kills the nonce
        vm.pauseGasMetering();
        QuarkWallet wallet = new QuarkWallet(address(0), address(0), codeJar, stateManager);
        vm.resumeGasMetering();
        vm.prank(address(wallet));
        /* although nonce=0 scriptAddress=0 is a zero-value for activeNonceScript, since the null script
         * cannot ever run any code, we do not need to care: we won't ever end up in a NonceScriptMismatch()
         * revert case since no active-nonce-gated operations can be invoked.
         */
        bytes memory result = stateManager.setActiveNonceAndCallback(0, address(0), bytes(""));
        assertEq(result, bytes(""));
    }

    function testScriptAddressIsEOA() public {
        // an EOA can be passed as scriptAddress and it will just return empty bytes
        vm.pauseGasMetering();
        QuarkWallet wallet = new QuarkWallet(address(0), address(0), codeJar, stateManager);
        vm.resumeGasMetering();
        vm.prank(address(wallet));
        bytes memory result = stateManager.setActiveNonceAndCallback(0, address(0x123), bytes(""));
        assertEq(result, bytes(""));
    }
}
