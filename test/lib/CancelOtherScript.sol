// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "../../src/QuarkWallet.sol";

contract CancelOtherScript {
    function run(uint256 nonce) public {
        return QuarkWallet(msg.sender).stateManager().setNonce(nonce);
    }
}
