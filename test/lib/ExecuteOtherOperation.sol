// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import "quark-core/src/QuarkWallet.sol";
import "quark-core/src/QuarkScript.sol";

contract ExecuteOtherOperation is QuarkScript {
    function run(QuarkWallet.QuarkOperation memory op, bytes memory signature) external returns (bytes memory) {
        // XXX: this should just be run(uint256,address,bytes) and use direct execute path
        allowCallback();
        return QuarkWallet(payable(address(this))).executeQuarkOperation(op, signature);
    }
}
