// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";
import {QuarkWallet, QuarkWalletStandalone} from "quark-core/src/QuarkWallet.sol";

import {YulHelper} from "test/lib/YulHelper.sol";
import {SignatureHelper} from "test/lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "test/lib/QuarkOperationHelper.sol";

import {Counter} from "test/lib/Counter.sol";
import {MaxCounterScript} from "test/lib/MaxCounterScript.sol";

contract QuarkStateManagerTest is Test {
    CodeJar public codeJar;
    QuarkStateManager public stateManager;

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        stateManager = new QuarkStateManager();
        console.log("QuarkStateManager deployed to: %s", address(stateManager));
    }

    function testRevertsForNoActiveNonce() public {
        // this contract does not have an active nonce
        vm.expectRevert(abi.encodeWithSelector(QuarkStateManager.NoActiveNonce.selector));
        stateManager.clearNonce();

        vm.expectRevert(abi.encodeWithSelector(QuarkStateManager.NoActiveNonce.selector));
        stateManager.read(bytes32("hello"));

        vm.expectRevert(abi.encodeWithSelector(QuarkStateManager.NoActiveNonce.selector));
        stateManager.write(bytes32("hello"), bytes32("goodbye"));

        vm.expectRevert(abi.encodeWithSelector(QuarkStateManager.NoActiveNonce.selector));
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
        QuarkWallet wallet = new QuarkWalletStandalone(address(0), address(0), codeJar, stateManager);
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

    function testRevertsIfScriptAddressIsNull() public {
        // the null script is not allowed, it will revert with EmptyCode
        vm.pauseGasMetering();
        QuarkWallet wallet = new QuarkWalletStandalone(address(0), address(0), codeJar, stateManager);
        vm.resumeGasMetering();
        vm.prank(address(wallet));
        vm.expectRevert(abi.encodeWithSelector(QuarkWallet.EmptyCode.selector));
        bytes memory result = stateManager.setActiveNonceAndCallback(0, address(0), bytes(""));
        assertEq(result, bytes(""));
    }

    function testRevertsIfScriptAddressIsEOA() public {
        // an EOA can be passed as scriptAddress and it will just return empty bytes
        vm.pauseGasMetering();
        QuarkWallet wallet = new QuarkWalletStandalone(address(0), address(0), codeJar, stateManager);
        vm.resumeGasMetering();
        vm.prank(address(wallet));
        vm.expectRevert(abi.encodeWithSelector(QuarkWallet.EmptyCode.selector));
        stateManager.setActiveNonceAndCallback(0, address(0x123), bytes(""));
    }

    function testReadStorageForWallet() public {
        // gas: disable metering except while executing operations
        vm.pauseGasMetering();

        Counter counter = new Counter();
        assertEq(counter.number(), 0);

        bytes memory maxCounterScript = new YulHelper().getDeployed("MaxCounterScript.sol/MaxCounterScript.json");
        address maxCounterScriptAddress = codeJar.saveCode(maxCounterScript);
        bytes memory call = abi.encodeWithSignature("run(address)", address(counter));

        QuarkWallet wallet = new QuarkWalletStandalone(address(0), address(0), codeJar, stateManager);

        vm.resumeGasMetering();

        assertEq(stateManager.walletStorage(address(wallet), 0, keccak256("count")), bytes32(uint256(0)));

        vm.prank(address(wallet));
        stateManager.setActiveNonceAndCallback(0, maxCounterScriptAddress, call);

        assertEq(stateManager.walletStorage(address(wallet), 0, keccak256("count")), bytes32(uint256(1)));

        vm.prank(address(wallet));
        stateManager.setActiveNonceAndCallback(0, maxCounterScriptAddress, call);

        assertEq(stateManager.walletStorage(address(wallet), 0, keccak256("count")), bytes32(uint256(2)));
    }
}
