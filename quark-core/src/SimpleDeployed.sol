// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

contract SimpleDeployed {
    constructor(bytes memory code) {
        assembly {
            return(add(code, 0x20), mload(code))
        }
    }
    function fun(uint256 x) external returns (uint256) {
        return x + 2;
    }
}
