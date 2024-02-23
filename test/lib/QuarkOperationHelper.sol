// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "quark-core/src/QuarkWallet.sol";

enum ScriptType {
    ScriptAddress,
    ScriptSource
}

// TODO: QuarkOperationHelper ScriptType doesn't really make sense anymore, since scriptSource
// has been replaced with scriptSources and scriptAddress is now always required.
contract QuarkOperationHelper is Test {
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
        address scriptAddress = wallet.codeJar().saveCode(scriptSource);
        if (scriptType == ScriptType.ScriptAddress) {
            return QuarkWallet.QuarkOperation({
                scriptAddress: scriptAddress,
                scriptSources: ensureScripts,
                scriptCalldata: scriptCalldata,
                nonce: wallet.stateManager().nextNonce(address(wallet)),
                expiry: block.timestamp + 1000
            });
        } else {
            return QuarkWallet.QuarkOperation({
                scriptAddress: scriptAddress,
                scriptSources: ensureScripts,
                scriptCalldata: scriptCalldata,
                nonce: wallet.stateManager().nextNonce(address(wallet)),
                expiry: block.timestamp + 1000
            });
        }
    }
}
