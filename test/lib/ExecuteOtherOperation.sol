// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../src/QuarkWallet.sol";

contract ExecuteOtherOperation {
    function run(QuarkWallet.QuarkOperation memory op, uint8 v, bytes32 r, bytes32 s) external returns (bytes memory) {
        return QuarkWallet(msg.sender).executeQuarkOperation(op, v, r, s);
    }
}