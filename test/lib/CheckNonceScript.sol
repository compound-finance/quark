// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import "quark-core/src/QuarkWallet.sol";
import "quark-core/src/QuarkScript.sol";

contract CheckNonceScript is QuarkScript {
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
