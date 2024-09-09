// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "quark-core/src/QuarkWallet.sol";

contract CancelOtherScript {
    event CancelNonce();

    function run() public {
        emit CancelNonce();
    }
}
