// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {CodeJar} from "codejar/src/CodeJar.sol";
import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";
import {QuarkWalletProxyFactory} from "quark-proxy/src/QuarkWalletProxyFactory.sol";
import {BatchExecutor} from "quark-core/src/periphery/BatchExecutor.sol";

/**
 * @title Quark Factory
 * @notice A factory for deploying all Quark related contracts to deterministic addresses
 * @author Compound Labs, Inc.
 */
contract QuarkFactory {
    CodeJar public codeJar;
    QuarkWallet public quarkWalletImp;
    QuarkWalletProxyFactory public quarkWalletProxyFactory;
    QuarkStateManager public quarkStateManager;
    BatchExecutor public batchExecutor;

    constructor() {}

    function deployQuarkContracts() external {
        codeJar = new CodeJar{salt: 0}();
        quarkStateManager = new QuarkStateManager{salt: 0}();
        quarkWalletImp = new QuarkWallet{salt: 0}(codeJar, quarkStateManager);
        quarkWalletProxyFactory = new QuarkWalletProxyFactory{salt: 0}(address(quarkWalletImp));
        batchExecutor = new BatchExecutor{salt: 0}();
    }
}
