// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

contract Multicall {
    error InvalidInput();
    error MulticallError(uint256 callIndex, address callContract, bytes err);

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
                revert MulticallError(i, callContracts[i], returnData);
            }
        }
    }

    /**
     * @notice Execute multiple calls
     * @param callContracts Array of contracts to call
     * @param callDatas Array of encoded calldata for each call
     * @param callValues Array of values for each call
     * @return returnDatas Array of return data for each call
     */
    function runWithReturns(address[] calldata callContracts, bytes[] calldata callDatas, uint256[] calldata callValues)
        external
        returns (bytes[] memory)
    {
        if (callContracts.length != callDatas.length || callContracts.length != callValues.length) {
            revert InvalidInput();
        }

        bytes[] memory returnDatas = new bytes[](callContracts.length);
        for (uint256 i = 0; i < callContracts.length; i++) {
            (bool success, bytes memory returnData) = callContracts[i].call{value: callValues[i]}(callDatas[i]);
            if (!success) {
                revert MulticallError(i, callContracts[i], returnData);
            }
            returnDatas[i] = returnData;
        }

        return returnDatas;
    }
}
