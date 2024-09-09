// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkNonceManager} from "quark-core/src/QuarkNonceManager.sol";
import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkWalletStandalone} from "quark-core/src/QuarkWalletStandalone.sol";

import {YulHelper} from "test/lib/YulHelper.sol";
import {SignatureHelper} from "test/lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "test/lib/QuarkOperationHelper.sol";

import {Logger} from "test/lib/Logger.sol";
import {Counter} from "test/lib/Counter.sol";
// import {MaxCounterScript} from "test/lib/MaxCounterScript.sol";

contract QuarkNonceManagerTest is Test {
    CodeJar public codeJar;
    QuarkNonceManager public nonceManager;

    /// @notice Represents the unclaimed bytes32 value.
    bytes32 public constant FREE_TOKEN = bytes32(uint256(0));

    /// @notice A token that implies a Quark Operation is no longer replayable.
    bytes32 public constant EXHAUSTED_TOKEN = bytes32(type(uint256).max);

    bytes32 public constant NONCE_ZERO = bytes32(uint256(0));
    bytes32 public constant NONCE_ONE = bytes32(uint256(1));

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        nonceManager = new QuarkNonceManager();
        console.log("QuarkNonceManager deployed to: %s", address(nonceManager));
    }

    function testNonceZeroIsValid() public {
        bytes32 nonce = bytes32(uint256(0));
        bytes32 EXHAUSTED = nonceManager.EXHAUSTED();

        // by default, nonce 0 is not set
        assertEq(nonceManager.getNonceSubmission(address(0x123), nonce), nonceManager.FREE());

        // nonce 0 can be set manually
        vm.prank(address(0x123));
        nonceManager.submitNonceToken(nonce, false, EXHAUSTED);
        assertEq(nonceManager.getNonceSubmission(address(0x123), nonce), nonceManager.EXHAUSTED());
    }

    function testClaimsSequentialNonces() public {
        for (uint256 i = 0; i <= 550; i++) {
            nonceManager.submitNonceToken(bytes32(i), false, EXHAUSTED_TOKEN);
        }

        for (uint256 i = 0; i <= 20; i++) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    QuarkNonceManager.NonReplayableNonce.selector,
                    address(this),
                    bytes32(i),
                    bytes32(type(uint256).max),
                    true
                )
            );
            nonceManager.submitNonceToken(bytes32(i), false, EXHAUSTED_TOKEN);
        }
    }

    function testRevertsIfNonceIsAlreadySet() public {
        bytes32 EXHAUSTED = nonceManager.EXHAUSTED();
        bytes32 nonce = bytes32(uint256(0));
        nonceManager.submitNonceToken(nonce, false, EXHAUSTED);

        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.NonReplayableNonce.selector, address(this), nonce, bytes32(type(uint256).max), true
            )
        );
        nonceManager.submitNonceToken(nonce, false, EXHAUSTED);
    }

    function testRevertsIfSubmittingNonExhaustedTokenForNonReplayable() public {
        bytes32 EXHAUSTED = nonceManager.EXHAUSTED();
        bytes32 nonce = bytes32(uint256(99));

        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, bytes32(0))
        );
        nonceManager.submitNonceToken(nonce, false, bytes32(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, bytes32(uint256(1))
            )
        );
        nonceManager.submitNonceToken(nonce, false, bytes32(uint256(1)));

        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, nonce)
        );
        nonceManager.submitNonceToken(nonce, false, nonce);
    }

    function testRevertsDefenseInDepthChangingReplayableness() public {
        bytes32 EXHAUSTED = nonceManager.EXHAUSTED();
        bytes32 nonceSecret = bytes32(uint256(99));
        bytes32 nonce = keccak256(abi.encodePacked(nonceSecret));

        nonceManager.submitNonceToken(nonce, true, nonce);

        // Reverts when isReplayable set to false
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.NonReplayableNonce.selector, address(this), nonce, nonceSecret, false
            )
        );
        nonceManager.submitNonceToken(nonce, false, nonceSecret);

        // Accepts when isReplayable set back to true
        nonceManager.submitNonceToken(nonce, true, nonceSecret);
    }

    function testRevertsDefenseInDepthReplayableSubmissionTokenZero() public {
        bytes32 nonce = bytes32(uint256(0));

        // Cannot set a submission token zero
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, nonce)
        );
        nonceManager.submitNonceToken(nonce, true, nonce);

        // Invalid as replayable with EXHAUSTED_TOKEN since submission token doesn't match
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, EXHAUSTED_TOKEN
            )
        );
        nonceManager.submitNonceToken(nonce, true, EXHAUSTED_TOKEN);

        // Still valid as non-replayable nonce
        nonceManager.submitNonceToken(nonce, false, EXHAUSTED_TOKEN);
    }

    function testIsSet() public {
        // nonce is unset by default
        assertEq(nonceManager.getNonceSubmission(address(this), NONCE_ZERO), FREE_TOKEN);

        // it can be set
        nonceManager.submitNonceToken(NONCE_ZERO, false, EXHAUSTED_TOKEN);
        assertEq(nonceManager.getNonceSubmission(address(this), NONCE_ZERO), EXHAUSTED_TOKEN);
    }

    function testNonLinearNonce() public {
        // nonce values are not incremental; you can use a random number as
        // long as it has not been set
        bytes32 nonce = bytes32(uint256(1234567890));

        assertEq(nonceManager.getNonceSubmission(address(this), NONCE_ZERO), FREE_TOKEN);

        nonceManager.submitNonceToken(nonce, false, EXHAUSTED_TOKEN);
        assertEq(nonceManager.getNonceSubmission(address(this), nonce), EXHAUSTED_TOKEN);

        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.NonReplayableNonce.selector, address(this), nonce, FREE_TOKEN, true
            )
        );
        nonceManager.submitNonceToken(nonce, false, FREE_TOKEN);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.NonReplayableNonce.selector, address(this), nonce, EXHAUSTED_TOKEN, true
            )
        );
        nonceManager.submitNonceToken(nonce, false, EXHAUSTED_TOKEN);
    }

    function testSingleUseRandomValidNonce() public {
        // nonce values are not incremental; you can use a random number as
        // long as it has not been set
        bytes32 nonce = bytes32(uint256(1234567890));
        bytes32 nonceHash = keccak256(abi.encodePacked(nonce));

        assertEq(nonceManager.getNonceSubmission(address(this), NONCE_ZERO), FREE_TOKEN);

        nonceManager.submitNonceToken(nonce, true, nonce);
        assertEq(nonceManager.getNonceSubmission(address(this), nonce), nonce);

        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, nonce)
        );
        nonceManager.submitNonceToken(nonce, true, nonce);
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, nonceHash)
        );
        nonceManager.submitNonceToken(nonce, true, nonceHash);
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, FREE_TOKEN)
        );
        nonceManager.submitNonceToken(nonce, true, FREE_TOKEN);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, EXHAUSTED_TOKEN
            )
        );
        nonceManager.submitNonceToken(nonce, true, EXHAUSTED_TOKEN);
    }

    function testNextNonceChain() public {
        // nonce values are not incremental; you can use a random number as
        // long as it has not been set
        bytes32 nonceSecret = bytes32(uint256(99));
        bytes32 replayToken2 = keccak256(abi.encodePacked(nonceSecret));
        bytes32 replayToken1 = keccak256(abi.encodePacked(replayToken2));
        bytes32 rootHash = keccak256(abi.encodePacked(replayToken1));
        bytes32 nonce = rootHash;

        assertEq(nonceManager.getNonceSubmission(address(this), nonce), FREE_TOKEN);

        nonceManager.submitNonceToken(nonce, true, rootHash);
        assertEq(nonceManager.getNonceSubmission(address(this), nonce), rootHash);

        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, rootHash)
        );
        nonceManager.submitNonceToken(nonce, true, rootHash);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, replayToken2
            )
        );
        nonceManager.submitNonceToken(nonce, true, replayToken2);
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, nonceSecret)
        );
        nonceManager.submitNonceToken(nonce, true, nonceSecret);
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, FREE_TOKEN)
        );
        nonceManager.submitNonceToken(nonce, true, FREE_TOKEN);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, EXHAUSTED_TOKEN
            )
        );
        nonceManager.submitNonceToken(nonce, true, EXHAUSTED_TOKEN);

        nonceManager.submitNonceToken(nonce, true, replayToken1);
        assertEq(nonceManager.getNonceSubmission(address(this), nonce), replayToken1);

        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, rootHash)
        );
        nonceManager.submitNonceToken(nonce, true, rootHash);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, replayToken1
            )
        );
        nonceManager.submitNonceToken(nonce, true, replayToken1);
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, nonceSecret)
        );
        nonceManager.submitNonceToken(nonce, true, nonceSecret);
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, FREE_TOKEN)
        );
        nonceManager.submitNonceToken(nonce, true, FREE_TOKEN);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, EXHAUSTED_TOKEN
            )
        );
        nonceManager.submitNonceToken(nonce, true, EXHAUSTED_TOKEN);

        nonceManager.submitNonceToken(nonce, true, replayToken2);
        assertEq(nonceManager.getNonceSubmission(address(this), nonce), replayToken2);

        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, rootHash)
        );
        nonceManager.submitNonceToken(nonce, true, rootHash);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, replayToken1
            )
        );
        nonceManager.submitNonceToken(nonce, true, replayToken1);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, replayToken2
            )
        );
        nonceManager.submitNonceToken(nonce, true, replayToken2);
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, FREE_TOKEN)
        );
        nonceManager.submitNonceToken(nonce, true, FREE_TOKEN);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, EXHAUSTED_TOKEN
            )
        );
        nonceManager.submitNonceToken(nonce, true, EXHAUSTED_TOKEN);

        nonceManager.submitNonceToken(nonce, true, nonceSecret);
        assertEq(nonceManager.getNonceSubmission(address(this), nonce), nonceSecret);

        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, rootHash)
        );
        nonceManager.submitNonceToken(nonce, true, rootHash);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, replayToken1
            )
        );
        nonceManager.submitNonceToken(nonce, true, replayToken1);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, replayToken2
            )
        );
        nonceManager.submitNonceToken(nonce, true, replayToken2);
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, nonceSecret)
        );
        nonceManager.submitNonceToken(nonce, true, nonceSecret);
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, FREE_TOKEN)
        );
        nonceManager.submitNonceToken(nonce, true, FREE_TOKEN);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, EXHAUSTED_TOKEN
            )
        );
        nonceManager.submitNonceToken(nonce, true, EXHAUSTED_TOKEN);
    }
}
