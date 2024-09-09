// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "quark-core/src/QuarkScript.sol";
import "quark-core/src/QuarkWallet.sol";

contract AllowCallbacks is QuarkScript {
    function run(address callbackAddress) public {
        QuarkWallet self = QuarkWallet(payable(address(this)));
        bytes32 CALLBACK_SLOT = self.CALLBACK_SLOT();
        bytes32 data = bytes32(uint256(uint160(callbackAddress)));
        assembly {
            sstore(CALLBACK_SLOT, data)
        }
    }

    function allowCallbackFun() public {
        allowCallback();
    }

    function clearCallbackFun() public {
        clearCallback();
    }
}
