// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "../../src/QuarkWallet.sol";
import "../../src/QuarkStorageManager.sol";

contract ExecuteWithRequirements {
    error RequirementNotMet(uint256 nonce);

    function runWithRequirements(uint256[] memory requirements, address scriptAddress, bytes calldata scriptCalldata) public returns (bytes memory) {
        QuarkWallet wallet = QuarkWallet(address(this));
        QuarkStorageManager storageManager = wallet.storageManager();
        for (uint256 i = 0; i < requirements.length; i++) {
            if (!storageManager.isNonceSet(address(wallet), requirements[i])) {
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
