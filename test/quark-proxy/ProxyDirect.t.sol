// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";

import {CodeJar} from "quark-core/src/CodeJar.sol";
import {ProxyDirect} from "quark-proxy/src/ProxyDirect.sol";
import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";

import {YulHelper} from "test/lib/YulHelper.sol";
import {SignatureHelper} from "test/lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "test/lib/QuarkOperationHelper.sol";

contract ProxyDirectTest is Test {
    CodeJar public codeJar;
    QuarkWallet public walletImplementation;
    QuarkStateManager public stateManager;

    uint256 alicePrivateKey = 0x8675309;
    address aliceAccount;
    ProxyDirect public aliceWalletProxy;

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to %s", address(codeJar));

        stateManager = new QuarkStateManager();
        console.log("QuarkStateManager deployed to %s", address(stateManager));

        walletImplementation = new QuarkWallet(address(0), address(0), codeJar, stateManager);
        console.log("QuarkWallet implementation deployed to %s", address(walletImplementation));

        aliceAccount = vm.addr(alicePrivateKey);
        console.log("aliceAccount: %s", aliceAccount);

        aliceWalletProxy = new ProxyDirect(address(walletImplementation), aliceAccount, address(0xabc));
        console.log("aliceWalletProxy deployed to %s", address(aliceWalletProxy));
    }

    function testSignerExecutor() public {
        assertEq(walletImplementation.signer(), address(0));
        assertEq(walletImplementation.executor(), address(0));

        assertEq(aliceWalletProxy.signer(), aliceAccount);
        assertEq(aliceWalletProxy.executor(), address(0xabc));

        bytes memory testScript = new YulHelper().getDeployed("ProxyDirect.t.sol/TestHarness.json");
        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            QuarkWallet(payable(aliceWalletProxy)),
            testScript,
            abi.encodeWithSignature("getSignerAndExecutor()"),
            ScriptType.ScriptAddress
        );
        (uint8 v, bytes32 r, bytes32 s) =
            new SignatureHelper().signOp(alicePrivateKey, QuarkWallet(payable(aliceWalletProxy)), op);
        bytes memory result = QuarkWallet(payable(aliceWalletProxy)).executeQuarkOperation(op, v, r, s);
        (address signer, address executor) = abi.decode(result, (address, address));
        assertEq(signer, aliceAccount);
        assertEq(executor, address(0xabc));
    }
}

import {QuarkScript} from "quark-core/src/QuarkScript.sol";

contract TestHarness is QuarkScript {
    function getSignerAndExecutor() public view returns (address, address) {
        return (signer(), executor());
    }
}