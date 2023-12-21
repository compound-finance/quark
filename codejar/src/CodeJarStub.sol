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
    constructor() payable {
        assembly {
            // Note: this short-circuits the constructor, which usually returns this contract's
            //       own "deployedCode" as its return value. Thus, the input `code` _becomes_
            //       this stub's deployedCode on chain, allowing you to deploy a contract
            //       with any runtime code.
            //
            // Note: `return`ing from a constructor is not documented in Solidity. This could be
            //       considered to breach on "undocumented" behavior. This functionality does
            //       **not** play well with const immutables.
            // Note: Magic numbers are weird. Here, we pick a number from observing the deployed size
            //       of this contract in the output of the build. A few points: a) we would prefer that
            //       we could do `type(CodeJarStub).creationCode.length` in this code, but that's
            //       expressly forbidden by Solidity. That would be fine, except in Solidity's own
            //       Yul code, they use `datasize("CodeJarStub")` and _that's_ okay for some reason,
            //       b) the idea of knowing where the constructor args start based on knowing the code size,
            //       via `datasize("CodeJarStub")` is perfectly normal and the only way to decode arguments,
            //       so the weird part here is simply the idea of hard-coding it since Solidity doesn't
            //       expose the size of the creation code itself to contracts, c) we tried to use
            //       `const programSz = type(CodeJarStubSize).creationCode.length` as a contract-constant,
            //       however, Solidity doesn't believe that to be a constant and thus creates runtime code
            //       for that. Weirdly `keccak256(type(CodeJarStubSize).creationCode)` is considered to be
            //       a constant, but I disgress, d) we test this value in a variety of ways. If the magic
            //       value truly changes, then the test cases would fail. We both check for it expressly,
            //       but also any test that relies on this working would immediately break otherwise.
            let programSz := 20 // It's magic. It's pure darned magic. Please don't look behind the curtain.
            let argSz := sub(codesize(), programSz)
            codecopy(0, programSz, argSz)
            return(0, argSz)
        }
    }
}
