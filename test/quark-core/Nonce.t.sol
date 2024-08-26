// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";

contract NonceTest is Test {
    QuarkStateManager public stateManager;

    /// @notice Represents the unclaimed bytes32 value.
    bytes32 public constant CLAIMABLE_TOKEN = bytes32(uint256(0));

    /// @notice A token that implies a Quark Operation is no longer replayable.
    bytes32 public constant NO_REPLAY_TOKEN = bytes32(type(uint256).max);

    bytes32 public constant NONCE_ZERO = bytes32(uint256(0));
    bytes32 public constant NONCE_ONE = bytes32(uint256(1));

    function setUp() public {
        stateManager = new QuarkStateManager();
        console.log("QuarkStateManager deployed to: %s", address(stateManager));
    }

    function testIsSet() public {
        // nonce is unset by default
        assertEq(stateManager.getNonceToken(address(this), NONCE_ZERO), CLAIMABLE_TOKEN);

        // it can be set
        stateManager.submitNonceToken(NONCE_ZERO, NO_REPLAY_TOKEN);
        assertEq(stateManager.getNonceToken(address(this), NONCE_ZERO), NO_REPLAY_TOKEN);
    }

    function testNonLinearNonce() public {
        // nonce values are not incremental; you can use a random number as
        // long as it has not been set
        bytes32 nonce = bytes32(uint256(1234567890));

        assertEq(stateManager.getNonceToken(address(this), NONCE_ZERO), CLAIMABLE_TOKEN);

        stateManager.submitNonceToken(nonce, NO_REPLAY_TOKEN);
        assertEq(stateManager.getNonceToken(address(this), nonce), NO_REPLAY_TOKEN);
    }

    // TODO: ADD TESTS FOR NONCE CHAIN
}
