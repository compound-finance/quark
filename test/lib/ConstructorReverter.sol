// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

contract ConstructorReverter {
    error Test(uint256);

    constructor() {
        revert Test(55);
    }
}