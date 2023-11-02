// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "../../src/QuarkWallet.sol";

contract ExecuteOnBehalf {
    function run(QuarkWallet targetWallet, uint256 nonce, address scriptAddress, bytes calldata scriptCalldata, bool allowCallback) public returns (bytes memory) {
        return targetWallet.executeQuarkOperation(nonce, scriptAddress, scriptCalldata, allowCallback);
    }
}
