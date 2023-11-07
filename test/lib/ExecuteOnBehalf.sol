// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "../../src/QuarkWallet.sol";

contract ExecuteOnBehalf {
    function run(QuarkWallet targetWallet, uint96 nonce, address scriptAddress, bytes calldata scriptCalldata)
        public
        returns (bytes memory)
    {
        return targetWallet.executeScript(nonce, scriptAddress, scriptCalldata);
    }
}
