// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";
import {QuarkNonceManager} from "quark-core/src/QuarkNonceManager.sol";

/**
 * @title Cancel Core Script
 * @notice Core transaction script that can be used to cancel quark operations.
 * @author Legend Labs, Inc.
 */
contract Cancel {
    /**
     * @notice May cancel a script by being run as a no-op (no operation).
     */
    function nop() external pure {}

    /**
     * @notice Cancels a script by calling into nonce manager to cancel the script's nonce.
     * @param nonce The nonce of the quark operation to cancel (exhaust)
     */
    function cancel(bytes32 nonce) external {
        nonceManager().cancel(nonce);
    }

    /**
     * @notice Cancels many scripts by calling into nonce manager to cancel each script's nonce.
     * @param nonces A list of nonces of the quark operations to cancel (exhaust)
     */
    function cancelMany(bytes32[] calldata nonces) external {
        QuarkNonceManager manager = nonceManager();
        for (uint256 i = 0; i < nonces.length; ++i) {
            bytes32 nonce = nonces[i];
            manager.cancel(nonce);
        }
    }

    function nonceManager() internal view returns (QuarkNonceManager) {
        return QuarkNonceManager(IQuarkWallet(address(this)).nonceManager());
    }
}
