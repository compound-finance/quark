// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {CodeJar} from "quark-core/src/CodeJar.sol";
import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";
import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkWalletFactory} from "quark-core/src/QuarkWalletFactory.sol";

contract QuarkFactory {
    CodeJar public immutable codeJar;
    QuarkStateManager public immutable stateManager;
    QuarkWalletFactory public immutable quarkWalletFactory;

    constructor() {
        codeJar = new CodeJar{salt: 0}();
        stateManager = new QuarkStateManager{salt: 0}();
        quarkWalletFactory = new QuarkWalletFactory{salt: 0}(codeJar, stateManager);
    }
}
