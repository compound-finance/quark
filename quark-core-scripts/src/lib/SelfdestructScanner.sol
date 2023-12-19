// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "forge-std/console.sol";

contract SelfdestructScanner {
    // References: https://www.evm.codes/?fork=shanghai
    bytes1 internal constant STOP = 0x00;
    bytes1 internal constant JUMPDEST = 0x5b;
    bytes1 internal constant PUSH1 = 0x60;
    bytes1 internal constant PUSH32 = 0x7f;
    bytes1 internal constant RETURN = 0xf3;
    bytes1 internal constant REVERT = 0xfd;
    bytes1 internal constant INVALID = 0xfe;
    bytes1 internal constant SELFDESTRUCT = 0xff;

    // function hasSelfdesturct(bytes memory code) internal pure returns (bool) {
    //     for (uint256 i = 0; i < code.length;) {
    //         if (code[i] == SELFDESTRUCT) {
    //             return true;
    //         } else if (code[i] >= PUSH1 && code[i] <= PUSH32) {
    //             i += uint256(uint8(code[i]) - uint8(PUSH1)) + 1;
    //         }

    //         unchecked {
    //             ++i;
    //         }
    //     }

    //     return false;
    // }

    function hasSelfdestructYul(bytes memory code) public pure returns (bool) {
        // Scan bytes and find selfdestruct opcode in Yul
        bool detectSelfdesturct;
        uint256 codeSize = code.length;
        assembly ("memory-safe") {
            for { let i := 0 } lt(i, codeSize) { i := add(i, 1) } {
                let opcode := mload(add(code, i))

                if eq(opcode, 0xff) {
                    detectSelfdesturct := true
                    break
                }

                if and(gt(opcode, 0x60), lt(opcode, 0x7f)) { i := add(i, add(sub(opcode, 0x60), 1)) }
            }

            detectSelfdesturct := false
        }

        return detectSelfdesturct;
    }
}
