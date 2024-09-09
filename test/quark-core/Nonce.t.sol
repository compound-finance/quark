// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkNonceManager} from "quark-core/src/QuarkNonceManager.sol";

contract NonceTest is Test {
    QuarkNonceManager public nonceManager;

    /// @notice Represents the unclaimed bytes32 value.
    bytes32 public constant FREE_TOKEN = bytes32(uint256(0));

    /// @notice A token that implies a Quark Operation is no longer replayable.
    bytes32 public constant EXHAUSTED_TOKEN = bytes32(type(uint256).max);

    bytes32 public constant NONCE_ZERO = bytes32(uint256(0));
    bytes32 public constant NONCE_ONE = bytes32(uint256(1));

    function setUp() public {
        nonceManager = new QuarkNonceManager();
        console.log("QuarkNonceManager deployed to: %s", address(nonceManager));
    }

    function testIsSet() public {
        // nonce is unset by default
        assertEq(nonceManager.getNonceSubmission(address(this), NONCE_ZERO), FREE_TOKEN);

        // it can be set
        nonceManager.submitNonceToken(NONCE_ZERO, EXHAUSTED_TOKEN);
        assertEq(nonceManager.getNonceSubmission(address(this), NONCE_ZERO), EXHAUSTED_TOKEN);
    }

    function testNonLinearNonce() public {
        // nonce values are not incremental; you can use a random number as
        // long as it has not been set
        bytes32 nonce = bytes32(uint256(1234567890));

        assertEq(nonceManager.getNonceSubmission(address(this), NONCE_ZERO), FREE_TOKEN);

        nonceManager.submitNonceToken(nonce, EXHAUSTED_TOKEN);
        assertEq(nonceManager.getNonceSubmission(address(this), nonce), EXHAUSTED_TOKEN);

        vm.expectRevert(abi.encodeWithSelector(QuarkNonceManager.NonReplayableNonce.selector, address(this), nonce, FREE_TOKEN));
        nonceManager.submitNonceToken(nonce, FREE_TOKEN);
        vm.expectRevert(abi.encodeWithSelector(QuarkNonceManager.NonReplayableNonce.selector, address(this), nonce, EXHAUSTED_TOKEN));
        nonceManager.submitNonceToken(nonce, EXHAUSTED_TOKEN);
    }

    function testSingleRandomValidNonce() public {
        // nonce values are not incremental; you can use a random number as
        // long as it has not been set
        bytes32 nonce = bytes32(uint256(1234567890));
        bytes32 nonceSecret = bytes32(uint256(99));
        bytes32 nonceSecretHash = keccak256(abi.encodePacked(nonceSecret));

        assertEq(nonceManager.getNonceSubmission(address(this), NONCE_ZERO), FREE_TOKEN);

        nonceManager.submitNonceToken(nonce, nonceSecret);
        assertEq(nonceManager.getNonceSubmission(address(this), nonce), nonceSecret);

        vm.expectRevert(abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, nonceSecret));
        nonceManager.submitNonceToken(nonce, nonceSecret);
        vm.expectRevert(abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, nonceSecretHash));
        nonceManager.submitNonceToken(nonce, nonceSecretHash);
        vm.expectRevert(abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, FREE_TOKEN));
        nonceManager.submitNonceToken(nonce, FREE_TOKEN);
        vm.expectRevert(abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, EXHAUSTED_TOKEN));
        nonceManager.submitNonceToken(nonce, EXHAUSTED_TOKEN);
    }

    function testNextNonceChain() public {
        // nonce values are not incremental; you can use a random number as
        // long as it has not been set
        bytes32 nonce = bytes32(uint256(1234567890));

        assertEq(nonceManager.getNonceSubmission(address(this), NONCE_ZERO), FREE_TOKEN);

        bytes32 nonceSecret = bytes32(uint256(99));
        bytes32 replayToken2 = keccak256(abi.encodePacked(nonceSecret));
        bytes32 replayToken1 = keccak256(abi.encodePacked(replayToken2));
        bytes32 rootHash = keccak256(abi.encodePacked(replayToken1));

        nonceManager.submitNonceToken(nonce, rootHash);
        assertEq(nonceManager.getNonceSubmission(address(this), nonce), rootHash);

        vm.expectRevert(abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, rootHash));
        nonceManager.submitNonceToken(nonce, rootHash);
        vm.expectRevert(abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, replayToken2));
        nonceManager.submitNonceToken(nonce, replayToken2);
        vm.expectRevert(abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, nonceSecret));
        nonceManager.submitNonceToken(nonce, nonceSecret);
        vm.expectRevert(abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, FREE_TOKEN));
        nonceManager.submitNonceToken(nonce, FREE_TOKEN);
        vm.expectRevert(abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, EXHAUSTED_TOKEN));
        nonceManager.submitNonceToken(nonce, EXHAUSTED_TOKEN);

        nonceManager.submitNonceToken(nonce, replayToken1);
        assertEq(nonceManager.getNonceSubmission(address(this), nonce), replayToken1);

        vm.expectRevert(abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, rootHash));
        nonceManager.submitNonceToken(nonce, rootHash);
        vm.expectRevert(abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, replayToken1));
        nonceManager.submitNonceToken(nonce, replayToken1);
        vm.expectRevert(abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, nonceSecret));
        nonceManager.submitNonceToken(nonce, nonceSecret);
        vm.expectRevert(abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, FREE_TOKEN));
        nonceManager.submitNonceToken(nonce, FREE_TOKEN);
        vm.expectRevert(abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, EXHAUSTED_TOKEN));
        nonceManager.submitNonceToken(nonce, EXHAUSTED_TOKEN);

        nonceManager.submitNonceToken(nonce, replayToken2);
        assertEq(nonceManager.getNonceSubmission(address(this), nonce), replayToken2);

        vm.expectRevert(abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, rootHash));
        nonceManager.submitNonceToken(nonce, rootHash);
        vm.expectRevert(abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, replayToken1));
        nonceManager.submitNonceToken(nonce, replayToken1);
        vm.expectRevert(abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, replayToken2));
        nonceManager.submitNonceToken(nonce, replayToken2);
        vm.expectRevert(abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, FREE_TOKEN));
        nonceManager.submitNonceToken(nonce, FREE_TOKEN);
        vm.expectRevert(abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, EXHAUSTED_TOKEN));
        nonceManager.submitNonceToken(nonce, EXHAUSTED_TOKEN);

        nonceManager.submitNonceToken(nonce, nonceSecret);
        assertEq(nonceManager.getNonceSubmission(address(this), nonce), nonceSecret);

        vm.expectRevert(abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, rootHash));
        nonceManager.submitNonceToken(nonce, rootHash);
        vm.expectRevert(abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, replayToken1));
        nonceManager.submitNonceToken(nonce, replayToken1);
        vm.expectRevert(abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, replayToken2));
        nonceManager.submitNonceToken(nonce, replayToken2);
        vm.expectRevert(abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, nonceSecret));
        nonceManager.submitNonceToken(nonce, nonceSecret);
        vm.expectRevert(abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, FREE_TOKEN));
        nonceManager.submitNonceToken(nonce, FREE_TOKEN);
        vm.expectRevert(abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, EXHAUSTED_TOKEN));
        nonceManager.submitNonceToken(nonce, EXHAUSTED_TOKEN);
    }

    // TODO: ADD TESTS FOR NONCE CHAIN
}
