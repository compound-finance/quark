// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "quark-core/src/QuarkWallet.sol";
import "quark-core/src/QuarkNonceManager.sol";

contract ExecuteWithRequirements {
    error RequirementNotMet(bytes32 nonce);

    function runWithRequirements(bytes32[] memory requirements, address scriptAddress, bytes calldata scriptCalldata)
        public
        returns (bytes memory)
    {
        QuarkWallet wallet = QuarkWallet(payable(address(this)));
        QuarkNonceManager nonceManager = wallet.nonceManager();
        for (uint256 i = 0; i < requirements.length; i++) {
            if (nonceManager.submissions(address(wallet), requirements[i]) == bytes32(uint256(0))) {
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
