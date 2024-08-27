// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkNonceManager} from "quark-core/src/QuarkNonceManager.sol";
import {QuarkWallet, IHasSignerExecutor} from "quark-core/src/QuarkWallet.sol";

/**
 * @title Quark Wallet Standalone
 * @notice Standalone extension of the Quark Wallet base class that does not require a proxy
 * @author Compound Labs, Inc.
 */
contract QuarkWalletStandalone is QuarkWallet, IHasSignerExecutor {
    /// @notice Address of the EOA signer or the EIP-1271 contract that verifies signed operations for this wallet
    address public immutable signer;

    /// @notice Address of the executor contract, if any, empowered to direct-execute unsigned operations for this wallet
    address public immutable executor;

    /**
     * @notice Construct a new QuarkWallet
     * @param signer_ The address that is allowed to sign QuarkOperations for this wallet
     * @param executor_ The address that is allowed to directly execute Quark scripts for this wallet
     * @param codeJar_ The CodeJar contract used to deploy scripts
     * @param nonceManager_ The QuarkNonceManager contract used to write/read nonces for this wallet
     */
    constructor(address signer_, address executor_, CodeJar codeJar_, QuarkNonceManager nonceManager_)
        QuarkWallet(codeJar_, nonceManager_)
    {
        signer = signer_;
        executor = executor_;
    }
}
