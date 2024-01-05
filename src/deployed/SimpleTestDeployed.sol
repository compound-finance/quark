// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

contract SimpleTestDeployed {
    constructor(bytes memory code) {
        assembly {
            return(add(code, 0x20), mload(code))
        }
    }
    function isTesters(address wallet, uint96 nonce) public view returns (bool) {
        return true;
    }
}
