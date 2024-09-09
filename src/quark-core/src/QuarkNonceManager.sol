// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";

/**
 * @title Quark Nonce Manager
 * @notice Contract for managing nonces for Quark wallets
 * @author Compound Labs, Inc.
 */
contract QuarkNonceManager {
    error NonReplayableNonce(address wallet, bytes32 nonce, bytes32 submissionToken, bool exhausted);
    error InvalidSubmissionToken(address wallet, bytes32 nonce, bytes32 submissionToken);

    event NonceSubmitted(address wallet, bytes32 nonce, bytes32 submissionToken);

    /// @notice Represents the unclaimed bytes32 value.
    bytes32 public constant FREE = bytes32(uint256(0));

    /// @notice A token that implies a Quark Operation is no longer replayable.
    bytes32 public constant EXHAUSTED = bytes32(type(uint256).max);

    /// @notice Mapping from nonces to last used submission token.
    mapping(address wallet => mapping(bytes32 nonce => bytes32 lastToken)) public submissions;

    /**
     * @notice Attempts a first or subsequent submission of a given nonce from a wallet.
     * @param nonce The nonce of the chain to submit.
     * @param isReplayable True only if the operation has been marked as replayable. Otherwise, submission token must be the EXHAUSTED value.
     * @param submissionToken The token for this submission. For single-use operations, set `submissionToken` to `uint256(-1)`. For first-use replayable operations, set `submissionToken` = `nonce`. Otherwise, the next submission token from the nonce-chain.
     */
    function submit(bytes32 nonce, bool isReplayable, bytes32 submissionToken) external {
        bytes32 lastTokenSubmission = submissions[msg.sender][nonce];
        if (lastTokenSubmission == EXHAUSTED) {
            revert NonReplayableNonce(msg.sender, nonce, submissionToken, true);
        }
        // Defense-in-deptch check for `submissionToken != FREE`
        if (submissionToken == FREE) {
            revert InvalidSubmissionToken(msg.sender, nonce, submissionToken);
        }

        bool validFirstPlay =
            lastTokenSubmission == FREE && (isReplayable ? submissionToken == nonce : submissionToken == EXHAUSTED);

        /*   validToken = validFirstPlay or (                  validReplay                                    ); */
        bool validToken = validFirstPlay || keccak256(abi.encodePacked(submissionToken)) == lastTokenSubmission;
        if (!validToken) {
            revert InvalidSubmissionToken(msg.sender, nonce, submissionToken);
        }

        // Note: even with a valid submission token, we always set non-replayables to exhausted (e.g. for cancelations)
        submissions[msg.sender][nonce] = isReplayable ? submissionToken : EXHAUSTED;
        emit NonceSubmitted(msg.sender, nonce, submissionToken);
    }
}
