// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.21;

import "../../src/QuarkWallet.sol";
import "../../src/QuarkScript.sol";

contract ExecuteOtherOperation is QuarkScript {
    function run(QuarkWallet.QuarkOperation memory op, uint8 v, bytes32 r, bytes32 s) external returns (bytes memory) {
        // XXX: this should just be run(uint256,address,bytes) and use direct execute path
        allowCallback();
        return QuarkWallet(msg.sender).executeQuarkOperation(op, v, r, s);
    }
}
