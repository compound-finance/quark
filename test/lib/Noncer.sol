// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "quark-core/src/QuarkScript.sol";

contract Noncer is QuarkScript {
    function checkNonce() public returns (bytes32) {
        return getActiveNonce();
    }

    function checkSubmissionToken() public returns (bytes32) {
        return getActiveSubmissionToken();
    }

    function checkReplayCount() public returns (uint256) {
        return getActiveReplayCount();
    }
}
