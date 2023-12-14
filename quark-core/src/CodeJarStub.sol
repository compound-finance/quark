// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

contract CodeJarStub {
    constructor(bytes memory code) {
        assembly {
            return(add(code, 0x20), mload(code))
        }
    }
}
