// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "quark-core/src/QuarkWallet.sol";
import {YulHelper} from "test/lib/YulHelper.sol";

enum ScriptType {
    ScriptAddress,
    ScriptSource
}

// TODO: QuarkOperationHelper ScriptType doesn't really make sense anymore, since scriptSource
// has been replaced with scriptSources and scriptAddress is now always required.
contract QuarkOperationHelper is Test {
    error SemiRandomNonceRequiresQuarkNonceManagerOrInitializedQuarkWallet(address quarkWallet);
    error Impossible();

    function newBasicOp(QuarkWallet wallet, bytes memory scriptSource, ScriptType scriptType)
        external
        returns (QuarkWallet.QuarkOperation memory)
    {
        return newBasicOpWithCalldata(wallet, scriptSource, abi.encode(), new bytes[](0), scriptType);
    }

    function newBasicOpWithCalldata(
        QuarkWallet wallet,
        bytes memory scriptSource,
        bytes memory scriptCalldata,
        ScriptType scriptType
    ) public returns (QuarkWallet.QuarkOperation memory) {
        return newBasicOpWithCalldata(wallet, scriptSource, scriptCalldata, new bytes[](0), scriptType);
    }

    function newBasicOpWithCalldata(
        QuarkWallet wallet,
        bytes memory scriptSource,
        bytes memory scriptCalldata,
        bytes[] memory ensureScripts,
        ScriptType scriptType
    ) public returns (QuarkWallet.QuarkOperation memory) {
        return newBasicOpWithCalldata(
            wallet, scriptSource, scriptCalldata, ensureScripts, scriptType, semiRandomNonce(wallet)
        );
    }

    function newBasicOpWithCalldata(
        QuarkWallet wallet,
        bytes memory scriptSource,
        bytes memory scriptCalldata,
        bytes[] memory ensureScripts,
        ScriptType scriptType,
        bytes32 nonce
    ) public returns (QuarkWallet.QuarkOperation memory) {
        address scriptAddress = wallet.codeJar().saveCode(scriptSource);
        if (scriptType == ScriptType.ScriptAddress) {
            return QuarkWallet.QuarkOperation({
                scriptAddress: scriptAddress,
                scriptSources: ensureScripts,
                scriptCalldata: scriptCalldata,
                nonce: nonce,
                isReplayable: false,
                expiry: block.timestamp + 1000
            });
        } else {
            return QuarkWallet.QuarkOperation({
                scriptAddress: scriptAddress,
                scriptSources: ensureScripts,
                scriptCalldata: scriptCalldata,
                nonce: nonce,
                isReplayable: false,
                expiry: block.timestamp + 1000
            });
        }
    }

    function newReplayableOpWithCalldata(
        QuarkWallet wallet,
        bytes memory scriptSource,
        bytes memory scriptCalldata,
        ScriptType scriptType,
        uint256 replays
    ) public returns (QuarkWallet.QuarkOperation memory, bytes32[] memory submissionTokens) {
        return newReplayableOpWithCalldata(wallet, scriptSource, scriptCalldata, new bytes[](0), scriptType, replays);
    }

    function newReplayableOpWithCalldata(
        QuarkWallet wallet,
        bytes memory scriptSource,
        bytes memory scriptCalldata,
        ScriptType scriptType,
        uint256 replays,
        bytes32 nonce
    ) public returns (QuarkWallet.QuarkOperation memory, bytes32[] memory submissionTokens) {
        return newReplayableOpWithCalldata(
            wallet, scriptSource, scriptCalldata, new bytes[](0), scriptType, replays, nonce
        );
    }

    function newReplayableOpWithCalldata(
        QuarkWallet wallet,
        bytes memory scriptSource,
        bytes memory scriptCalldata,
        bytes[] memory ensureScripts,
        ScriptType scriptType,
        uint256 replays
    ) public returns (QuarkWallet.QuarkOperation memory, bytes32[] memory submissionTokens) {
        return newReplayableOpWithCalldata(
            wallet, scriptSource, scriptCalldata, ensureScripts, scriptType, replays, semiRandomNonce(wallet)
        );
    }

    function newReplayableOpWithCalldata(
        QuarkWallet wallet,
        bytes memory scriptSource,
        bytes memory scriptCalldata,
        bytes[] memory ensureScripts,
        ScriptType scriptType,
        uint256 replays,
        bytes32 nonce
    ) public returns (QuarkWallet.QuarkOperation memory, bytes32[] memory submissionTokens) {
        QuarkWallet.QuarkOperation memory operation =
            newBasicOpWithCalldata(wallet, scriptSource, scriptCalldata, ensureScripts, scriptType, nonce);
        submissionTokens = new bytes32[](replays + 1);
        submissionTokens[replays] = nonce;
        for (uint256 i = 0; i < replays; i++) {
            nonce = keccak256(abi.encodePacked(nonce));
            submissionTokens[replays - i - 1] = nonce;
        }
        operation.nonce = nonce;
        operation.isReplayable = true;
        return (operation, submissionTokens);
    }

    function cancelReplayableByNop(QuarkWallet wallet, QuarkWallet.QuarkOperation memory quarkOperation)
        public
        returns (QuarkWallet.QuarkOperation memory)
    {
        return getCancelOperation(wallet, quarkOperation.nonce, abi.encodeWithSignature("nop()"));
    }

    function cancelReplayableByNewOp(QuarkWallet wallet, QuarkWallet.QuarkOperation memory quarkOperation)
        public
        returns (QuarkWallet.QuarkOperation memory)
    {
        return getCancelOperation(
            wallet, semiRandomNonce(wallet), abi.encodeWithSignature("run(bytes32)", quarkOperation.nonce)
        );
    }

    function getCancelOperation(QuarkWallet wallet, bytes32 selfNonce, bytes memory callData)
        public
        returns (QuarkWallet.QuarkOperation memory)
    {
        bytes memory cancelOtherScript = new YulHelper().getCode("CancelOtherScript.sol/CancelOtherScript.json");
        address scriptAddress = wallet.codeJar().saveCode(cancelOtherScript);
        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = cancelOtherScript;
        return QuarkWallet.QuarkOperation({
            scriptAddress: scriptAddress,
            scriptSources: scriptSources,
            scriptCalldata: callData,
            nonce: selfNonce,
            isReplayable: false,
            expiry: block.timestamp + 1000
        });
    }

    /// @dev Note: not sufficiently random for non-test case usage.
    function semiRandomNonce(QuarkWallet wallet) public view returns (bytes32) {
        if (address(wallet).code.length == 0) {
            revert SemiRandomNonceRequiresQuarkNonceManagerOrInitializedQuarkWallet(address(wallet));
        }

        return semiRandomNonce(wallet.nonceManager(), wallet);
    }

    /// @dev Note: not sufficiently random for non-test case usage.
    function semiRandomNonce(QuarkNonceManager quarkNonceManager, QuarkWallet wallet) public view returns (bytes32) {
        bytes32 nonce = bytes32(uint256(keccak256(abi.encodePacked(block.timestamp))) - 1);
        while (true) {
            if (quarkNonceManager.submissions(address(wallet), nonce) == bytes32(uint256(0))) {
                return nonce;
            }

            nonce = bytes32(uint256(keccak256(abi.encodePacked(nonce))) - 1);
        }
        revert Impossible();
    }

    function incrementNonce(bytes32 nonce) public pure returns (bytes32) {
        return bytes32(uint256(nonce) + 1);
    }
}
