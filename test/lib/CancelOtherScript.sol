// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "quark-core/src/QuarkWallet.sol";

contract CancelOtherScript {
    function run(bytes32 nonce) public {
        return QuarkWallet(payable(address(this))).nonceManager().submitNonceToken(nonce, bytes32(type(uint256).max));
    }
}
