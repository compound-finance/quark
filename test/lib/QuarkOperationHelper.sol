// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "./../../src/QuarkWallet.sol";

enum ScriptType {
    ScriptAddress,
    ScriptSource
}

contract QuarkOperationHelper is Test {
    function newBasicOp(QuarkWallet wallet, bytes memory scriptSource, ScriptType scriptType)
        external
        returns (QuarkWallet.QuarkOperation memory)
    {
        return newBasicOpWithCalldata(wallet, scriptSource, abi.encode(), scriptType);
    }

    function newBasicOpWithCalldata(
        QuarkWallet wallet,
        bytes memory scriptSource,
        bytes memory scriptCalldata,
        ScriptType scriptType
    ) public returns (QuarkWallet.QuarkOperation memory) {
        address scriptAddress = wallet.codeJar().saveCode(scriptSource);
        if (scriptType == ScriptType.ScriptAddress) {
            return QuarkWallet.QuarkOperation({
                scriptAddress: scriptAddress,
                scriptSource: "",
                scriptCalldata: scriptCalldata,
                nonce: wallet.stateManager().nextNonce(address(wallet)),
                expiry: block.timestamp + 1000
            });
        } else {
            return QuarkWallet.QuarkOperation({
                scriptAddress: address(0),
                scriptSource: scriptSource,
                scriptCalldata: scriptCalldata,
                nonce: wallet.stateManager().nextNonce(address(wallet)),
                expiry: block.timestamp + 1000
            });
        }
    }
}
