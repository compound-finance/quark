// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "forge-std/console.sol";

import {CodeJar} from "quark-core/src/CodeJar.sol";
import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";
import {AbstractQuarkWalletFactory} from "quark-core/src/AbstractQuarkWalletFactory.sol";

import {QuarkWalletProxyFactory} from "quark-proxy/src/QuarkWalletProxyFactory.sol";

import {AbstractQuarkWalletFactoryTest} from "test/lib/AbstractQuarkWalletFactoryTest.sol";

contract QuarkWalletProxyFactoryTest is AbstractQuarkWalletFactoryTest {
    QuarkWalletProxyFactory public factoryImplementation;

    constructor() {
        factoryImplementation = new QuarkWalletProxyFactory();
        factory = AbstractQuarkWalletFactory(factoryImplementation);
        console.log("QuarkWalletFactory deployed to: %s", address(factory));

        console.log("wallet implementation address is: %s", factoryImplementation.walletImplementation());

        codeJar = factoryImplementation.codeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        stateManager = factoryImplementation.stateManager();
        console.log("QuarkStateManager deployed to: %s", address(stateManager));
    }

    /* ===== sanity checks ===== */

    function testVersion() public {
        assertEq(factory.VERSION(), 1);
    }

    function testCreatesCodejar() public {
        assertNotEq(address(factoryImplementation.codeJar()), address(0));
    }
}
