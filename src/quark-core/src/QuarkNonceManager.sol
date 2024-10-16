// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

library QuarkNonceManagerMetadata {
    /// @notice Represents the unclaimed bytes32 value.
    bytes32 internal constant FREE = bytes32(uint256(0));

    /// @notice A token that implies a Quark Operation is no longer replayable.
    bytes32 internal constant EXHAUSTED = bytes32(type(uint256).max);
}

/**
 * @title Quark Nonce Manager
 * @notice Contract for managing nonces for Quark wallets
 * @author Compound Labs, Inc.
 */
contract QuarkNonceManager {
    error NonReplayableNonce(address wallet, bytes32 nonce, bytes32 submissionToken);
    error InvalidNonce(address wallet, bytes32 nonce);
    error InvalidSubmissionToken(address wallet, bytes32 nonce, bytes32 submissionToken);

    event NonceSubmitted(address indexed wallet, bytes32 indexed nonce, bytes32 submissionToken);

    /// @notice Represents the unclaimed bytes32 value.
    bytes32 public constant FREE = QuarkNonceManagerMetadata.FREE;

    /// @notice A token that implies a Quark Operation is no longer replayable.
    bytes32 public constant EXHAUSTED = QuarkNonceManagerMetadata.EXHAUSTED;

    /// @notice Mapping from nonces to last used submission token.
    mapping(address wallet => mapping(bytes32 nonce => bytes32 lastToken)) public submissions;

    /**
     * @notice Ensures a given nonce is canceled for sender. An un-used nonce will not be usable in the future, and a replayable nonce will no longer be replayable. This is a no-op for already canceled operations.
     * @param nonce The nonce of the chain to cancel.
     */
    function cancel(bytes32 nonce) external {
        submissions[msg.sender][nonce] = EXHAUSTED;
        emit NonceSubmitted(msg.sender, nonce, EXHAUSTED);
    }

    /**
     * @notice Attempts a first or subsequent submission of a given nonce from a wallet.
     * @param nonce The nonce of the Quark operation to submit. This value is the root of the nonce-chain that the submissionToken is a part of.
     * @param isReplayable True only if the operation has been marked as replayable. Otherwise, submission token must be the EXHAUSTED value.
     * @param submissionToken The token for this submission. For single-use operations and first-use replayable operations, set `submissionToken` = `nonce`. Otherwise, the next submission token from the nonce-chain.
     */
    function submit(bytes32 nonce, bool isReplayable, bytes32 submissionToken) external {
        bytes32 lastTokenSubmission = submissions[msg.sender][nonce];
        if (lastTokenSubmission == EXHAUSTED) {
            revert NonReplayableNonce(msg.sender, nonce, submissionToken);
        }
        // Defense-in-depth check for `nonce != FREE` and `nonce != EXHAUSTED`
        if (nonce == FREE || nonce == EXHAUSTED) {
            revert InvalidNonce(msg.sender, nonce);
        }
        // Defense-in-depth check for `submissionToken != FREE` and `submissionToken != EXHAUSTED`
        if (submissionToken == FREE || submissionToken == EXHAUSTED) {
            revert InvalidSubmissionToken(msg.sender, nonce, submissionToken);
        }

        bool validFirstPlay = lastTokenSubmission == FREE && submissionToken == nonce;

        /* let validFirstPlayOrReplay = validFirstPlay or validReplay [with short-circuiting] */
        bool validFirstPlayOrReplay =
            validFirstPlay || keccak256(abi.encodePacked(submissionToken)) == lastTokenSubmission;

        if (!validFirstPlayOrReplay) {
            revert InvalidSubmissionToken(msg.sender, nonce, submissionToken);
        }

        // Note: Even with a valid submission token, we always set non-replayables to exhausted (e.g. for cancellations)
        bytes32 finalSubmissionToken = isReplayable ? submissionToken : EXHAUSTED;
        submissions[msg.sender][nonce] = finalSubmissionToken;
        emit NonceSubmitted(msg.sender, nonce, finalSubmissionToken);
    }
}
