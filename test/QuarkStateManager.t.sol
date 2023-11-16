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
        vm.expectRevert();
        stateManager.clearNonce();
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

        vm.pauseGasMetering();
        QuarkWallet wallet = new QuarkWallet(address(0), address(0), codeJar, stateManager);
        vm.resumeGasMetering();
        vm.prank(address(wallet));
        bytes memory result = stateManager.setActiveNonceAndCallback(0, address(0x123), bytes(""));
        assertEq(result, bytes(""));
    }
}
