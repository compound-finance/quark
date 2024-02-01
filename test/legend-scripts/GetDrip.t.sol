// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "legend-scripts/src/GetDrip.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {QuarkWalletProxyFactory} from "quark-proxy/src/QuarkWalletProxyFactory.sol";
import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {CodeJar} from "codejar/src/CodeJar.sol";
import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";
import {YulHelper} from "test/lib/YulHelper.sol";
import {QuarkOperationHelper, ScriptType} from "test/lib/QuarkOperationHelper.sol";
import {SignatureHelper} from "test/lib/SignatureHelper.sol";

/**
 * Tests approve and execute against 0x
 */
contract GetDripTest is Test {
    QuarkWalletProxyFactory public factory;
    uint256 alicePrivateKey = 0xa11ce;
    address alice = vm.addr(alicePrivateKey);
    address constant USDC = 0x07865c6E87B9F70255377e024ace6630C1Eaa37F;

    function setUp() public {
        // Fork setup
        vm.createSelectFork("https://goerli.infura.io/v3/531e3eb124194de5a88caec726d10bea");
        factory = new QuarkWalletProxyFactory(address(new QuarkWallet(new CodeJar(), new QuarkStateManager())));
    }

    // Tests dripping some usdc
    function testDrip() public {
        vm.pauseGasMetering();

        QuarkWallet wallet = QuarkWallet(factory.create(alice, alice));
        new YulHelper().deploy("GetDrip.sol/GetDrip.json");

        bytes memory legendScript = new YulHelper().getDeployed("GetDrip.sol/GetDrip.json");

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet, legendScript, abi.encodeCall(GetDrip.drip, (USDC)), ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        vm.resumeGasMetering();

        assertEq(IERC20(USDC).balanceOf(address(wallet)), 0);
        wallet.executeQuarkOperation(op, v, r, s);

        // The drip always gives this amount
        assertEq(IERC20(USDC).balanceOf(address(wallet)), 29808084);
    }
}
