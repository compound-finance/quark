// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";

contract QuarkStateManagerHarness is QuarkStateManager {
    function readRawUnsafe(QuarkWallet wallet, uint96 nonce, string memory key) external view returns (bytes32) {
        return walletStorage[address(wallet)][nonce][keccak256(bytes(key))];
    }
}
