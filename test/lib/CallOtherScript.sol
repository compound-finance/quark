// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "quark-core/src/QuarkScript.sol";
import "quark-core/src/QuarkWallet.sol";

contract CallOtherScript is QuarkScript {
    function call(uint96 nonce, address scriptAddress, bytes calldata scriptCalldata) public {
        // Anti-pattern to clear replay first, but this is necessary to hit our edge case
        allowReplay();
        QuarkWallet(payable(address(this))).stateManager().setActiveNonceAndCallback(
            nonce, scriptAddress, scriptCalldata
        );
        QuarkWallet(payable(address(this))).stateManager().setNonce(nonce);
    }
}
