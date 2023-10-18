// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract ConditionChecks {
    error CheckFailed();

    /**
     * @dev Check if two addresses is equal
     * @param data The address to check in bytes
     * @param checkData The address to check with in bytes
     */
    function addressEq(bytes calldata data, bytes calldata checkData) external pure {
        // Only revert if condition isn't met
        if (abi.decode(data, (address)) != abi.decode(checkData, (address))) {
            revert CheckFailed();
        }
    }

    /**
     * @dev Compare two bytes, revert if not equal
     * @param data The bytes to compare
     * @param checkData The bytes to compare with
     */
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

    /**
     * @dev Check if the data is true
     * @param data The bool data to check in bytes
     */
    function isTrue(bytes calldata data) external pure {
        // Only revert if condition isn't met
        if (!abi.decode(data, (bool))) {
            revert CheckFailed();
        }
    }

    /**
     * @dev Check if the data is false
     * @param data The bool data to check in bytes
     */
    function isFalse(bytes calldata data) external pure {
        // Only revert if condition isn't met
        if (abi.decode(data, (bool))) {
            revert CheckFailed();
        }
    }

    /**
     * @dev Check if the data is equal to checkData in uint256
     * @param data The uint256 data to check in bytes
     * @param checkData The uint256 data to check with in bytes
     */
    function uint256Eq(bytes calldata data, bytes calldata checkData) external pure {
        // Only revert if condition isn't met
        if (abi.decode(data, (uint256)) != abi.decode(checkData, (uint256))) {
            revert CheckFailed();
        }
    }

    /**
     * @dev Check if the data is greater than checkData in uint256
     * @param data The uint256 data to check in bytes
     * @param checkData The uint256 data to check with in bytes
     */
    function uint256Gt(bytes calldata data, bytes calldata checkData) external pure {
        // Only revert if condition isn't met
        if (abi.decode(data, (uint256)) <= abi.decode(checkData, (uint256))) {
            revert CheckFailed();
        }
    }

    /**
     * @dev Check if the data is greater than or equal to checkData in uint256
     * @param data The uint256 data to check in bytes
     * @param checkData The uint256 data to check with in bytes
     */
    function uint256Gte(bytes calldata data, bytes calldata checkData) external pure {
        // Only revert if condition isn't met
        if (abi.decode(data, (uint256)) < abi.decode(checkData, (uint256))) {
            revert CheckFailed();
        }
    }

    /**
     * @dev Check if the data is less than to checkData in uint256
     * @param data The uint256 data to check in bytes
     * @param checkData The uint256 data to check with in bytes
     */
    function uint256Lt(bytes calldata data, bytes calldata checkData) external pure {
        // Only revert if condition isn't met
        if (abi.decode(data, (uint256)) >= abi.decode(checkData, (uint256))) {
            revert CheckFailed();
        }
    }

    /**
     * @dev Check if the data is less than or equal to checkData in uint256
     * @param data The uint256 data to check in bytes
     * @param checkData The uint256 data to check with in bytes
     */
    function uint256Lte(bytes calldata data, bytes calldata checkData) external pure {
        // Only revert if condition isn't met
        if (abi.decode(data, (uint256)) > abi.decode(checkData, (uint256))) {
            revert CheckFailed();
        }
    }
}
