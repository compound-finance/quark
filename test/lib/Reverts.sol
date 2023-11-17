// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

contract Reverts {
    error Whoops();

    fallback() external {
        revert Whoops();
    }
}
