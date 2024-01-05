// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

/**
 * @title Code Jar Stub
 * @notice A contract which short-circuits in its constructor to return its own input as deployed code.
 * @author Compound Labs, Inc.
 */
contract CodeJarStub {
    /**
     * @notice Constructor which returns its input instead of the code of this shell contract
     * @dev This allows us to deterministically deploy arbitrary code
     */
    constructor(bytes memory code) payable {
        assembly ("memory-safe") {
            // Note: this short-circuits the constructor, which usually returns this contract's
            //       own "deployedCode" as its return value. Thus, the input `code` _becomes_
            //       this stub's deployedCode on chain, allowing you to deploy a contract
            //       with any runtime code.
            //
            // Note: `return`ing from a constructor is not documented in Solidity. This could be
            //       considered to breach on "undocumented" behavior. This functionality does
            //       **not** play well with const immutables.
            return(add(code, 0x20), mload(code))
        }
    }
}