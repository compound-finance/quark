// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import {CodeJar} from "codejar/src/CodeJar.sol";

contract Reverts {
    error Whoops();

    function divideByZero() external pure {
        uint256(100) / uint256(0);
    }

    function revertSeven() external pure {
        uint256 p;
        assembly {
            p := mload(0x40) // free-memory pointer
            mstore(0x40, add(p, 0x20)) // allocate 32 bytes
            mstore(p, 0x07) // store 7 at that 32 byte space
            revert(p, 0x20)
        }
    }

    function outOfGas() external view {
        while (gasleft() >= 0) {}
    }

    function invalidOpcode(CodeJar codeJar) external {
        // Deploys code that uses the INVALID (0xFE) opcode
        bytes memory byteCode = abi.encodePacked(hex"FE");
        address scriptAddress = codeJar.saveCode(byteCode);

        (bool success, bytes memory result) = scriptAddress.call(hex"");
        if (!success) {
            assembly {
                revert(add(result, 0x20), mload(result))
            }
        }
    }

    fallback() external {
        revert Whoops();
    }
}
