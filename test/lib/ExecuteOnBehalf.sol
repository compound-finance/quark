// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "quark-core/src/QuarkWallet.sol";

contract ExecuteOnBehalf {
    function run(QuarkWallet targetWallet, bytes32 nonce, address scriptAddress, bytes calldata scriptCalldata)
        public
        returns (bytes memory)
    {
        return targetWallet.executeScript(nonce, scriptAddress, scriptCalldata, new bytes[](0));
    }
}
