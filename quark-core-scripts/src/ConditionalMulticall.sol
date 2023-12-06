// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "quark-core-scripts/src/lib/ConditionalChecker.sol";

contract ConditionalMulticall {
    error InvalidInput();
    error MulticallError(uint256 callIndex, address callContract, bytes err);

    /**
     * @notice Execute multiple calls with conditional checks
     * @param callContracts Array of contracts to call
     * @param callDatas Array of encoded calldata for each call
     * @param conditions Array of conditions specifying check types and operators
     * @param checkValues Array of expected values for checks
     */
    function run(
        address[] calldata callContracts,
        bytes[] calldata callDatas,
        ConditionalChecker.Condition[] calldata conditions,
        bytes[] calldata checkValues
    ) external returns (bytes[] memory) {
        if (
            callContracts.length != callDatas.length || callContracts.length != conditions.length
                || callContracts.length != checkValues.length
        ) {
            revert InvalidInput();
        }

        bytes[] memory returnDatas = new bytes[](callContracts.length);
        for (uint256 i = 0; i < callContracts.length; i++) {
            (bool success, bytes memory returnData) = callContracts[i].delegatecall(callDatas[i]);
            if (!success) {
                revert MulticallError(i, callContracts[i], returnData);
            }
            if (
                conditions[i].checkType != ConditionalChecker.CheckType.None
                    && conditions[i].operator != ConditionalChecker.Operator.None
            ) {
                ConditionalChecker.check(abi.decode(returnData, (bytes)), checkValues[i], conditions[i]);
            }

            returnDatas[i] = abi.decode(returnData, (bytes));
        }

        return returnDatas;
    }
}
