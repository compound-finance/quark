// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "quark-core/src/QuarkWallet.sol";

contract AllowCallbacks {
    function run(address callbackAddress) public {
        QuarkWallet self = QuarkWallet(payable(address(this)));
        self.stateManager().write(self.CALLBACK_KEY(), bytes32(uint256(uint160(callbackAddress))));
    }
}
