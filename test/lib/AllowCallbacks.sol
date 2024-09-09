// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "quark-core/src/QuarkScript.sol";
import "quark-core/src/QuarkWallet.sol";

contract AllowCallbacks is QuarkScript {
    // TODO: Uncomment when replay tokens are supported
    // function run(address callbackAddress) public {
    //     QuarkWallet self = QuarkWallet(payable(address(this)));
    //     self.nonceManager().write(self.CALLBACK_KEY(), bytes32(uint256(uint160(callbackAddress))));
    // }

    function allowCallbackAndReplay() public {
        allowCallback();
        // TODO: Uncomment when replay tokens are supported
        // allowReplay();
    }

    function clear() public {
        clearCallback();
    }
}
