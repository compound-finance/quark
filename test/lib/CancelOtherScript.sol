// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "../../src/QuarkWallet.sol";

contract CancelOtherScript {
    function run(uint96 nonce) public {
        return QuarkWallet(payable(address(this))).stateManager().setNonce(nonce);
    }
}
