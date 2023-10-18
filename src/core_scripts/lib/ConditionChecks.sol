// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract ConditionChecks {
    error CheckFailed();

    function addressEq(bytes calldata data, bytes calldata checkData) external pure {
        address addrLeft = abi.decode(data, (address));
        address addrRight = abi.decode(checkData, (address));

        // Only revert if condition didn't meet
        if (addrLeft != addrRight) {
            revert CheckFailed();
        }
    }

    function bytesEq(bytes calldata data, bytes calldata checkData) external pure {
        if (data.length != checkData.length) {
            revert CheckFailed();
        }

        for (uint256 i = 0; i < data.length; i++) {
            if (data[i] != checkData[i]) {
                revert CheckFailed();
            }
        }
    }

    function isTrue(bytes calldata data) external pure {
        bool checkValue = abi.decode(data, (bool));

        // Only revert if condition didn't meet
        if (!checkValue) {
            revert CheckFailed();
        }
    }

    function isFalse(bytes calldata data) external pure {
        bool checkValue = abi.decode(data, (bool));

        // Only revert if condition didn't meet
        if (checkValue) {
            revert CheckFailed();
        }
    }

    function uint256Eq(bytes calldata data, bytes calldata checkData) external pure {
        uint256 left = abi.decode(data, (uint256));
        uint256 right = abi.decode(checkData, (uint256));

        // Only revert if condition didn't meet
        if (left != right) {
            revert CheckFailed();
        }
    }

    function uint256Gt(bytes calldata data, bytes calldata checkData) external pure {
        uint256 left = abi.decode(data, (uint256));
        uint256 right = abi.decode(checkData, (uint256));

        // Only revert if condition didn't meet
        if (left <= right) {
            revert CheckFailed();
        }
    }

    function uint256Gte(bytes calldata data, bytes calldata checkData) external pure {
        uint256 left = abi.decode(data, (uint256));
        uint256 right = abi.decode(checkData, (uint256));

        // Only revert if condition didn't meet
        if (left < right) {
            revert CheckFailed();
        }
    }

    function uint256Lt(bytes calldata data, bytes calldata checkData) external pure {
        uint256 left = abi.decode(data, (uint256));
        uint256 right = abi.decode(checkData, (uint256));

        // Only revert if condition didn't meet
        if (left >= right) {
            revert CheckFailed();
        }
    }

    function uint256Lte(bytes calldata data, bytes calldata checkData) external pure {
        uint256 left = abi.decode(data, (uint256));
        uint256 right = abi.decode(checkData, (uint256));

        // Only revert if condition didn't meet
        if (left > right) {
            revert CheckFailed();
        }
    }
}
