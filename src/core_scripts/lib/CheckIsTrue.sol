// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
contract CheckIsTrue {
    error CheckFailed();
    /**
     * @dev Check if the data is false
     * @param data The data to check
     */
    function check(bytes calldata data) external pure {
        bool checkValue = abi.decode(data, (bool));

        // Only revert if condition didn't meet
        if (!checkValue) {
            revert CheckFailed();
        }
    }
}