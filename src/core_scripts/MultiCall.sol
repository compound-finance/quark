// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "./lib/ConditionalChecker.sol";

contract MultiCall {
    error InvalidInput();
    error MultiCallError(uint256 callIndex, address callContract, bytes callData, uint256 callValue, bytes err);

    /**
     * @notice Execute multiple calls
     * @param callContracts Array of contracts to call
     * @param callDatas Array of encoded calldata for each call
     * @param callValues Array of values for each call
     */
    function run(address[] calldata callContracts, bytes[] calldata callDatas, uint256[] calldata callValues)
        external
    {
        if (callContracts.length != callDatas.length || callContracts.length != callValues.length) {
            revert InvalidInput();
        }

        for (uint256 i = 0; i < callContracts.length; i++) {
            (bool success, bytes memory returnData) = callContracts[i].call{value: callValues[i]}(callDatas[i]);
            if (!success) {
                revert MultiCallError(i, callContracts[i], callDatas[i], callValues[i], returnData);
            }
        }
    }

    /**
     * @notice Execute multiple calls with conditional checks
     * @param callContracts Array of contracts to call
     * @param callDatas Array of encoded calldata for each call
     * @param callValues Array of values for each call
     * @param checkType Array of types for checks
     * @param operator Array of operators for checks
     * @param checkValues Array of expected values for checks
     */
    function runWithConditionalCheck(
        address[] calldata callContracts,
        bytes[] calldata callDatas,
        uint256[] calldata callValues,
        ConditionalChecker.CheckType[] calldata checkType,
        ConditionalChecker.Operator[] calldata operator,
        bytes[] calldata checkValues
    ) external {
        if (
            callContracts.length != callDatas.length || callContracts.length != callValues.length
                || callContracts.length != checkType.length || callContracts.length != operator.length
                || callContracts.length != checkValues.length
        ) {
            revert InvalidInput();
        }

        for (uint256 i = 0; i < callContracts.length; i++) {
            (bool success, bytes memory returnData) = callContracts[i].call{value: callValues[i]}(callDatas[i]);
            if (!success) {
                revert MultiCallError(i, callContracts[i], callDatas[i], callValues[i], returnData);
            }
            if (checkType[i] != ConditionalChecker.CheckType.None && operator[i] != ConditionalChecker.Operator.None) {
                ConditionalChecker.check(returnData, checkValues[i], checkType[i], operator[i]);
            }
        }
    }
}
