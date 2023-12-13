// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "forge-std/console.sol";

import {CodeJar} from "quark-core/src/CodeJar.sol";
import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";
import {QuarkWalletFactory} from "quark-core/src/QuarkWalletFactory.sol";
import {AbstractQuarkWalletFactory} from "quark-core/src/AbstractQuarkWalletFactory.sol";

import {AbstractQuarkWalletFactoryTest} from "test/lib/AbstractQuarkWalletFactoryTest.sol";

contract QuarkWalletFactoryTest is AbstractQuarkWalletFactoryTest {
    QuarkWalletFactory public factoryImplementation;

    constructor() {
        factoryImplementation = new QuarkWalletFactory();
        factory = AbstractQuarkWalletFactory(factoryImplementation);
        console.log("QuarkWalletFactory deployed to: %s", address(factory));

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
