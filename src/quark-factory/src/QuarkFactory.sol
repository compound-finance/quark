// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import {CodeJar} from "codejar/src/CodeJar.sol";
import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkNonceManager} from "quark-core/src/QuarkNonceManager.sol";
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
    QuarkNonceManager public quarkNonceManager;
    BatchExecutor public batchExecutor;

    constructor(CodeJar codeJar_) {
        codeJar = codeJar_;
    }

    function deployQuarkContracts() external {
        quarkNonceManager =
            QuarkNonceManager(payable(codeJar.saveCode(abi.encodePacked(type(QuarkNonceManager).creationCode))));
        quarkWalletImpl = QuarkWallet(
            payable(
                codeJar.saveCode(
                    abi.encodePacked(type(QuarkWallet).creationCode, abi.encode(codeJar, quarkNonceManager))
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
