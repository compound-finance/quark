// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

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
    CodeJar public immutable codeJar;
    QuarkWallet public quarkWalletImpl;
    QuarkWalletProxyFactory public quarkWalletProxyFactory;
    QuarkStateManager public quarkStateManager;
    BatchExecutor public batchExecutor;

    constructor(CodeJar codeJar_) {
        codeJar = codeJar_;
    }

    function deployQuarkContracts() external {
        quarkStateManager =
            QuarkStateManager(payable(codeJar.saveCode(abi.encodePacked(type(QuarkStateManager).creationCode))));
        quarkWalletImpl = QuarkWallet(
            payable(
                codeJar.saveCode(
                    abi.encodePacked(type(QuarkWallet).creationCode, abi.encode(codeJar, quarkStateManager))
                )
            )
        );
        quarkWalletProxyFactory = QuarkWalletProxyFactory(
            payable(
                codeJar.saveCode(
                    abi.encodePacked(type(QuarkWalletProxyFactory).creationCode, abi.encode(quarkWalletImpl))
                )
            )
        );
        batchExecutor = BatchExecutor(payable(codeJar.saveCode(abi.encodePacked(type(BatchExecutor).creationCode))));
    }
}
