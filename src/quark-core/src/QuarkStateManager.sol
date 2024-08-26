// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import {IQuarkWallet} from "quark-core/src/interfaces/IQuarkWallet.sol";

/**
 * @title Quark State Manager
 * @notice Contract for managing nonces for Quark wallets
 * @author Compound Labs, Inc.
 */
contract QuarkStateManager {
    error NonReplayableNonce(address wallet, bytes32 nonce, bytes32 replayToken);
    error InvalidReplayToken(address wallet, bytes32 nonce, bytes32 replayToken);

    event NonceSubmitted(address wallet, bytes32 nonce, bytes32 replayToken);

    /// @notice Represents the unclaimed bytes32 value.
    bytes32 public constant CLAIMABLE_TOKEN = bytes32(uint256(0));

    /// @notice A token that implies a Quark Operation is no longer replayable.
    bytes32 public constant NO_REPLAY_TOKEN = bytes32(type(uint).max);

    /// @notice Mapping from nonces to last used replay token.
    mapping(address wallet => mapping(bytes32 nonce => bytes32 lastToken)) public nonceTokens;

    /**
     * @notice Returns the nonce token (last replay token) for a given nonce. For finalized scripts, this will be `uint256(-1)`. For unclaimed nonces, this will be `uint256(0)`. Otherwise, it will be the next value in the replay chain.
     * @param wallet The wallet for which to get the nonce token.
     * @param nonce The nonce for the given request.
     * @return replayToken The last used replay token, or 0 if unused or -1 if finalized.
     */
    function getNonceToken(address wallet, bytes32 nonce) external view returns (bytes32 replayToken) {
        return nonceTokens[wallet][nonce];
    }

    /**
     * @notice Attempts a first or subsequent submission of a given nonce from a wallet.
     * @param nonce The nonce of the chain to submit.
     * @param replayToken The replay token of the submission. For single-use operations, set `replayToken` to `uint256(-1)`. For first-use replayable operations, set `replayToken` = `nonce`.
     */
    function submitNonceToken(bytes32 nonce, bytes32 replayToken) external {
        bytes32 lastToken = nonceTokens[msg.sender][nonce];
        if (lastToken == NO_REPLAY_TOKEN) {
            revert NonReplayableNonce(msg.sender, nonce, replayToken);
        }

        bool validReplay = lastToken == CLAIMABLE_TOKEN || keccak256(abi.encodePacked(replayToken)) == lastToken;
        if (!validReplay) {
            revert InvalidReplayToken(msg.sender, nonce, replayToken);
        }

        nonceTokens[msg.sender][nonce] = replayToken;
        emit NonceSubmitted(msg.sender, nonce, replayToken);
    }
}
