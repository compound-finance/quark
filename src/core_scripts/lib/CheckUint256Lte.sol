// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
contract CheckUint256Lte {
    error CheckFailed();
    function check(bytes calldata data, bytes calldata checkData) external pure {
        uint256 left = abi.decode(data, (uint256));
        uint256 right = abi.decode(checkData, (uint256));

        // Only revert if condition didn't meet
        if (left > right) {
            revert CheckFailed();
        }
    }
}