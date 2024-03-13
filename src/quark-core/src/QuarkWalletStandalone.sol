// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";
import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {HasSignerExecutor} from "quark-core/src/interfaces/HasSignerExecutor.sol";

/**
 * @title Quark Wallet Standalone
 * @notice Standalone extension of the Quark Wallet base class that does not require a proxy
 * @author Compound Labs, Inc.
 */
contract QuarkWalletStandalone is QuarkWallet, HasSignerExecutor {
    /// @notice Address of the EOA signer or the EIP-1271 contract that verifies signed operations for this wallet
    address public immutable signer;

    /// @notice Address of the executor contract, if any, empowered to direct-execute unsigned operations for this wallet
    address public immutable executor;

    /**
     * @notice Construct a new QuarkWallet
     * @param signer_ The address that is allowed to sign QuarkOperations for this wallet
     * @param executor_ The address that is allowed to directly execute Quark scripts for this wallet
     * @param codeJar_ The CodeJar contract used to deploy scripts
     * @param stateManager_ The QuarkStateManager contract used to write/read nonces and storage for this wallet
     */
    constructor(address signer_, address executor_, CodeJar codeJar_, QuarkStateManager stateManager_)
        QuarkWallet(codeJar_, stateManager_)
    {
        signer = signer_;
        executor = executor_;
    }
}
