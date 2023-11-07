// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "../../src/QuarkWallet.sol";

contract CancelOtherScript {
    function run(uint96 nonce) public {
        return QuarkWallet(address(this)).stateManager().setNonce(nonce);
    }
}
