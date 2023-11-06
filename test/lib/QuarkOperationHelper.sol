// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "./../../src/CodeJar.sol";
import "./../../src/QuarkWallet.sol";

enum ScriptType {
    ScriptAddress,
    ScriptSource
}

contract QuarkOperationHelper is Test {
    function newBasicOp(QuarkWallet wallet, CodeJar codeJar, bytes memory scriptSource, ScriptType scriptType)
        external
        returns (QuarkWallet.QuarkOperation memory)
    {
        return newBasicOpWithCalldata(wallet, codeJar, scriptSource, abi.encode(), scriptType);
    }

    function newBasicOpWithCalldata(
        QuarkWallet wallet,
        CodeJar codeJar,
        bytes memory scriptSource,
        bytes memory scriptCalldata,
        ScriptType scriptType
    ) public returns (QuarkWallet.QuarkOperation memory) {
        address scriptAddress = codeJar.saveCode(scriptSource);
        if (scriptType == ScriptType.ScriptAddress) {
            return QuarkWallet.QuarkOperation({
                scriptAddress: scriptAddress,
                scriptSource: "",
                scriptCalldata: scriptCalldata,
                nonce: wallet.nextNonce(),
                expiry: block.timestamp + 1000
            });
        } else {
            return QuarkWallet.QuarkOperation({
                scriptAddress: address(0),
                scriptSource: scriptSource,
                scriptCalldata: scriptCalldata,
                nonce: wallet.nextNonce(),
                expiry: block.timestamp + 1000
            });
        }
    }
}
