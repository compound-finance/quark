// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

interface CodeJar {
    function saveCode(bytes memory code) external returns (address);
}

contract Redeployer {
    address public immutable deployed;

    constructor(bytes memory deploy) {
        deployed = CodeJar(msg.sender).saveCode(deploy);
    }
}
