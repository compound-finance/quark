// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "quark-core/src/QuarkWallet.sol";
import "quark-core/src/QuarkStateManager.sol";

contract ExecuteWithRequirements {
    error RequirementNotMet(uint96 nonce);

    function runWithRequirements(uint96[] memory requirements, address scriptAddress, bytes calldata scriptCalldata)
        public
        returns (bytes memory)
    {
        QuarkWallet wallet = QuarkWallet(payable(address(this)));
        QuarkStateManager stateManager = wallet.stateManager();
        for (uint96 i = 0; i < requirements.length; i++) {
            if (!stateManager.isNonceSet(address(wallet), requirements[i])) {
                revert RequirementNotMet(requirements[i]);
            }
        }
        (bool success, bytes memory result) = scriptAddress.call(scriptCalldata);
        // if the inner call does not succeed, propagate the error
        if (!success) {
            assembly {
                revert(add(result, 0x20), mload(result))
            }
        }
        return result;
    }
}
