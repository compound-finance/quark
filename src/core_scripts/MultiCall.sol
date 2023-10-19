// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

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
}
