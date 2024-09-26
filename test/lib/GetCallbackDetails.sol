// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import {QuarkWalletMetadata} from "quark-core/src/QuarkWallet.sol";
import {QuarkScript} from "quark-core/src/QuarkScript.sol";

contract GetCallbackDetails is QuarkScript {
    function getCallbackAddress() public returns (address) {
        bytes32 callbackSlot = QuarkWalletMetadata.CALLBACK_SLOT;
        address callbackAddress;
        assembly {
            callbackAddress := tload(callbackSlot)
        }
        return callbackAddress;
    }
}
