// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

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

    function testNonceOneIsValid() public {
        bytes32 nonce = bytes32(uint256(1));

        // by default, nonce 1 is not set
        assertEq(nonceManager.submissions(address(0x123), nonce), nonceManager.FREE());

        // nonce 1 can be set manually
        vm.prank(address(0x123));
        nonceManager.submit(nonce, false, nonce);
        assertEq(nonceManager.submissions(address(0x123), nonce), nonceManager.EXHAUSTED());
    }

    function testInvalidNonces() public {
        vm.expectRevert(abi.encodeWithSelector(QuarkNonceManager.InvalidNonce.selector, address(this), bytes32(0)));
        nonceManager.submit(bytes32(0), false, bytes32(0));

        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidNonce.selector, address(this), bytes32(type(uint256).max))
        );
        nonceManager.submit(bytes32(type(uint256).max), false, bytes32(type(uint256).max));
    }

    function testClaimsSequentialNonces() public {
        for (uint256 i = 1; i <= 550; i++) {
            nonceManager.submit(bytes32(i), false, bytes32(i));
        }

        for (uint256 i = 1; i <= 20; i++) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    QuarkNonceManager.NonReplayableNonce.selector, address(this), bytes32(i), bytes32(type(uint256).max)
                )
            );
            nonceManager.submit(bytes32(i), false, EXHAUSTED_TOKEN);
        }
    }

    function testRevertsIfNonceIsAlreadySet() public {
        bytes32 EXHAUSTED = nonceManager.EXHAUSTED();
        bytes32 nonce = bytes32(uint256(1));
        nonceManager.submit(nonce, false, nonce);

        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.NonReplayableNonce.selector, address(this), nonce, nonce)
        );
        nonceManager.submit(nonce, false, nonce);

        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.NonReplayableNonce.selector, address(this), nonce, EXHAUSTED)
        );
        nonceManager.submit(nonce, false, EXHAUSTED);
    }

    function testRevertsIfSubmittingNonMatchingNonceForNonReplayable() public {
        bytes32 nonce = bytes32(uint256(99));

        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, bytes32(0))
        );
        nonceManager.submit(nonce, false, bytes32(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, bytes32(uint256(1))
            )
        );
        nonceManager.submit(nonce, false, bytes32(uint256(1)));

        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, EXHAUSTED_TOKEN
            )
        );
        nonceManager.submit(nonce, false, EXHAUSTED_TOKEN);
    }

    function testChangingReplayableness() public {
        bytes32 nonceSecret = bytes32(uint256(99));
        bytes32 nonce = keccak256(abi.encodePacked(nonceSecret));

        nonceManager.submit(nonce, true, nonce);

        // Accepts as a cancel
        nonceManager.submit(nonce, false, nonceSecret);

        assertEq(nonceManager.submissions(address(this), nonce), EXHAUSTED_TOKEN);

        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.NonReplayableNonce.selector, address(this), nonce, nonceSecret)
        );
        nonceManager.submit(nonce, true, nonceSecret);
    }

    function testRevertsDefenseInDepthReplayableSubmissionTokenZero() public {
        bytes32 nonce = bytes32(uint256(1));

        // Cannot set a submission token zero
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, bytes32(0))
        );
        nonceManager.submit(nonce, true, bytes32(0));

        // Cannot set a submission token to EXHAUSTED_TOKEN
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, EXHAUSTED_TOKEN
            )
        );
        nonceManager.submit(nonce, true, EXHAUSTED_TOKEN);

        // Still valid as non-replayable nonce
        nonceManager.submit(nonce, false, nonce);
    }

    function testNonReplayableEmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit QuarkNonceManager.NonceSubmitted(address(this), NONCE_ONE, EXHAUSTED_TOKEN);
        nonceManager.submit(NONCE_ONE, false, NONCE_ONE);

        assertEq(nonceManager.submissions(address(this), NONCE_ONE), EXHAUSTED_TOKEN);
    }

    function testReplayableEmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit QuarkNonceManager.NonceSubmitted(address(this), NONCE_ONE, NONCE_ONE);
        nonceManager.submit(NONCE_ONE, true, NONCE_ONE);

        assertEq(nonceManager.submissions(address(this), NONCE_ONE), NONCE_ONE);
    }

    function testIsSet() public {
        // nonce is unset by default
        assertEq(nonceManager.submissions(address(this), NONCE_ONE), FREE_TOKEN);

        // it can be set
        nonceManager.submit(NONCE_ONE, false, NONCE_ONE);
        assertEq(nonceManager.submissions(address(this), NONCE_ONE), EXHAUSTED_TOKEN);
    }

    function testNonLinearNonce() public {
        // nonce values are not incremental; you can use a random number as
        // long as it has not been set
        bytes32 nonce = bytes32(uint256(1234567890));

        assertEq(nonceManager.submissions(address(this), NONCE_ONE), FREE_TOKEN);

        nonceManager.submit(nonce, false, nonce);
        assertEq(nonceManager.submissions(address(this), nonce), EXHAUSTED_TOKEN);

        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.NonReplayableNonce.selector, address(this), nonce, FREE_TOKEN)
        );
        nonceManager.submit(nonce, false, FREE_TOKEN);
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.NonReplayableNonce.selector, address(this), nonce, EXHAUSTED_TOKEN)
        );
        nonceManager.submit(nonce, false, EXHAUSTED_TOKEN);
    }

    function testSingleUseRandomValidNonce() public {
        // nonce values are not incremental; you can use a random number as
        // long as it has not been set
        bytes32 nonce = bytes32(uint256(1234567890));
        bytes32 nonceHash = keccak256(abi.encodePacked(nonce));

        assertEq(nonceManager.submissions(address(this), NONCE_ONE), FREE_TOKEN);

        nonceManager.submit(nonce, true, nonce);
        assertEq(nonceManager.submissions(address(this), nonce), nonce);

        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, nonce)
        );
        nonceManager.submit(nonce, true, nonce);
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, nonceHash)
        );
        nonceManager.submit(nonce, true, nonceHash);
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, FREE_TOKEN)
        );
        nonceManager.submit(nonce, true, FREE_TOKEN);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, EXHAUSTED_TOKEN
            )
        );
        nonceManager.submit(nonce, true, EXHAUSTED_TOKEN);
    }

    function testNextNonceChain() public {
        // nonce values are not incremental; you can use a random number as
        // long as it has not been set
        bytes32 nonceSecret = bytes32(uint256(99));
        bytes32 submissionToken2 = keccak256(abi.encodePacked(nonceSecret));
        bytes32 submissionToken1 = keccak256(abi.encodePacked(submissionToken2));
        bytes32 nonce = keccak256(abi.encodePacked(submissionToken1));

        assertEq(nonceManager.submissions(address(this), nonce), FREE_TOKEN);

        nonceManager.submit(nonce, true, nonce);
        assertEq(nonceManager.submissions(address(this), nonce), nonce);

        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, nonce)
        );
        nonceManager.submit(nonce, true, nonce);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, submissionToken2
            )
        );
        nonceManager.submit(nonce, true, submissionToken2);
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, nonceSecret)
        );
        nonceManager.submit(nonce, true, nonceSecret);
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, FREE_TOKEN)
        );
        nonceManager.submit(nonce, true, FREE_TOKEN);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, EXHAUSTED_TOKEN
            )
        );
        nonceManager.submit(nonce, true, EXHAUSTED_TOKEN);

        nonceManager.submit(nonce, true, submissionToken1);
        assertEq(nonceManager.submissions(address(this), nonce), submissionToken1);

        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, nonce)
        );
        nonceManager.submit(nonce, true, nonce);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, submissionToken1
            )
        );
        nonceManager.submit(nonce, true, submissionToken1);
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, nonceSecret)
        );
        nonceManager.submit(nonce, true, nonceSecret);
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, FREE_TOKEN)
        );
        nonceManager.submit(nonce, true, FREE_TOKEN);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, EXHAUSTED_TOKEN
            )
        );
        nonceManager.submit(nonce, true, EXHAUSTED_TOKEN);

        nonceManager.submit(nonce, true, submissionToken2);
        assertEq(nonceManager.submissions(address(this), nonce), submissionToken2);

        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, nonce)
        );
        nonceManager.submit(nonce, true, nonce);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, submissionToken1
            )
        );
        nonceManager.submit(nonce, true, submissionToken1);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, submissionToken2
            )
        );
        nonceManager.submit(nonce, true, submissionToken2);
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, FREE_TOKEN)
        );
        nonceManager.submit(nonce, true, FREE_TOKEN);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, EXHAUSTED_TOKEN
            )
        );
        nonceManager.submit(nonce, true, EXHAUSTED_TOKEN);

        nonceManager.submit(nonce, true, nonceSecret);
        assertEq(nonceManager.submissions(address(this), nonce), nonceSecret);

        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, nonce)
        );
        nonceManager.submit(nonce, true, nonce);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, submissionToken1
            )
        );
        nonceManager.submit(nonce, true, submissionToken1);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, submissionToken2
            )
        );
        nonceManager.submit(nonce, true, submissionToken2);
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, nonceSecret)
        );
        nonceManager.submit(nonce, true, nonceSecret);
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, FREE_TOKEN)
        );
        nonceManager.submit(nonce, true, FREE_TOKEN);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.InvalidSubmissionToken.selector, address(this), nonce, EXHAUSTED_TOKEN
            )
        );
        nonceManager.submit(nonce, true, EXHAUSTED_TOKEN);
    }

    function testCancelChain() public {
        bytes32 nonceSecret = bytes32(uint256(99));
        bytes32 submissionToken2 = keccak256(abi.encodePacked(nonceSecret));
        bytes32 submissionToken1 = keccak256(abi.encodePacked(submissionToken2));
        bytes32 nonce = keccak256(abi.encodePacked(submissionToken1));

        assertEq(nonceManager.submissions(address(this), nonce), FREE_TOKEN);

        nonceManager.submit(nonce, true, nonce);
        assertEq(nonceManager.submissions(address(this), nonce), nonce);

        nonceManager.cancel(nonce);
        assertEq(nonceManager.submissions(address(this), nonce), EXHAUSTED_TOKEN);

        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.NonReplayableNonce.selector, address(this), nonce, nonce)
        );
        nonceManager.submit(nonce, true, nonce);

        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.NonReplayableNonce.selector, address(this), nonce, submissionToken2
            )
        );
        nonceManager.submit(nonce, true, submissionToken2);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkNonceManager.NonReplayableNonce.selector, address(this), nonce, submissionToken1
            )
        );
        nonceManager.submit(nonce, true, submissionToken1);
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.NonReplayableNonce.selector, address(this), nonce, nonceSecret)
        );
        nonceManager.submit(nonce, true, nonceSecret);
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.NonReplayableNonce.selector, address(this), nonce, EXHAUSTED_TOKEN)
        );
        nonceManager.submit(nonce, true, EXHAUSTED_TOKEN);
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.NonReplayableNonce.selector, address(this), nonce, FREE_TOKEN)
        );
        nonceManager.submit(nonce, true, FREE_TOKEN);
    }

    function testPrecancelNonce() public {
        bytes32 nonce = bytes32(uint256(1));

        vm.prank(address(0x123));
        nonceManager.cancel(nonce);

        // by default, nonce 1 is not set
        assertEq(nonceManager.submissions(address(0x123), nonce), nonceManager.EXHAUSTED());

        // nonce 1 can be set manually
        vm.prank(address(0x123));
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.NonReplayableNonce.selector, address(0x123), nonce, nonce)
        );
        nonceManager.submit(nonce, false, nonce);
        assertEq(nonceManager.submissions(address(0x123), nonce), nonceManager.EXHAUSTED());
    }

    function testCancelExhaustedIsNoOp() public {
        bytes32 nonce = bytes32(uint256(1));

        // by default, nonce 1 is not set
        assertEq(nonceManager.submissions(address(0x123), nonce), nonceManager.FREE());

        // nonce 1 can be set manually
        vm.prank(address(0x123));
        nonceManager.submit(nonce, false, nonce);
        assertEq(nonceManager.submissions(address(0x123), nonce), nonceManager.EXHAUSTED());

        vm.prank(address(0x123));
        nonceManager.cancel(nonce);

        assertEq(nonceManager.submissions(address(0x123), nonce), nonceManager.EXHAUSTED());
    }
}
