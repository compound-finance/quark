// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "quark-core/src/QuarkScript.sol";
import "quark-core/src/QuarkWallet.sol";

contract AllowCallbacks is QuarkScript {
    function run(address callbackAddress) public {
        QuarkWallet self = QuarkWallet(payable(address(this)));
        self.stateManager().write(self.CALLBACK_KEY(), bytes32(uint256(uint160(callbackAddress))));
    }

    function allowCallbackAndReplay() public {
        allowCallback();
        allowReplay();
    }

    function clear() public {
        clearCallback();
    }
}
