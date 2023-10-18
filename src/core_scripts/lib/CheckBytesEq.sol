// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
contract CheckBytesEq {
    error CheckFailed();
    function check(bytes calldata data, bytes calldata checkData) external pure {
        if (data.length != checkData.length) {
            revert CheckFailed();
        }

        for (uint256 i = 0; i < data.length; i++) {
            if (data[i] != checkData[i]) {
                revert CheckFailed();
            }
        }
    }
}