// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "quark-core/src/QuarkWallet.sol";
import "quark-core/src/QuarkScript.sol";

contract CancelOtherScript is QuarkScript {
    event Nop();
    event CancelNonce(bytes32 nonce);

    function nop() public {
        emit Nop();
    }

    function run(bytes32 nonce) public {
        nonceManager().cancel(nonce);
        emit CancelNonce(nonce);
    }

    function checkNonce() public view returns (bytes32) {
        return getActiveNonce();
    }

    function checkSubmissionToken() public view returns (bytes32) {
        return getActiveSubmissionToken();
    }

    function checkReplayCount() public view returns (uint256) {
        return getActiveReplayCount();
    }
}
