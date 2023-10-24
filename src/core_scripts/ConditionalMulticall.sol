// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "./lib/ConditionalChecker.sol";

contract ConditionalMulticall {
    error InvalidInput();
    error MulticallError(uint256 callIndex, address callContract, bytes err);

    /**
     * @notice Execute multiple calls with conditional checks
     * @param callContracts Array of contracts to call
     * @param callDatas Array of encoded calldata for each call
     * @param callValues Array of values for each call
     * @param conditions Array of conditions specifying check types and operators
     * @param checkValues Array of expected values for checks
     */
    function run(
        address[] calldata callContracts,
        bytes[] calldata callDatas,
        uint256[] calldata callValues,
        ConditionalChecker.Condition[] calldata conditions,
        bytes[] calldata checkValues
    ) external returns (bytes[] memory) {
        if (
            callContracts.length != callDatas.length || callContracts.length != callValues.length
                || callContracts.length != conditions.length || callContracts.length != checkValues.length
        ) {
            revert InvalidInput();
        }

        bytes[] memory returnDatas = new bytes[](callContracts.length);
        for (uint256 i = 0; i < callContracts.length; i++) {
            (bool success, bytes memory returnData) = callContracts[i].call{value: callValues[i]}(callDatas[i]);
            if (!success) {
                revert MulticallError(i, callContracts[i], returnData);
            }
            if (
                conditions[i].checkType != ConditionalChecker.CheckType.None
                    && conditions[i].operator != ConditionalChecker.Operator.None
            ) {
                ConditionalChecker.check(returnData, checkValues[i], conditions[i]);
            }

            returnDatas[i] = returnData;
        }

        return returnDatas;
    }
}
