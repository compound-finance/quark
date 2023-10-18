// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./CoreScript.sol";

contract MultiCall is CoreScript {
    /**
     * @notice Execute multiple calls in a single transaction
     * @param callContracts Array of contracts to call
     * @param callDatas Array of calldatas to call
     * @param callValues Array of values to call
     */
    function run(address[] calldata callContracts, bytes[] calldata callDatas, uint256[] calldata callValues)
        external
    {
        executeMultiInternal(callContracts, callDatas, callValues);
    }

    /**
     * @notice Execute multiple calls in a single transaction with checks
     * @param callContracts Array of contracts to call
     * @param callDatas Array of calldatas to call
     * @param callValues Array of values to call
     * @param checkContracts Array of check contracts
     * @param checkValues Array of values to compare in check
     * @return Return return data from the last contract call
     */
    function runWithChecks(
        address[] calldata callContracts,
        bytes[] calldata callDatas,
        uint256[] calldata callValues,
        address[] calldata checkContracts,
        bytes[] calldata checkValues
    ) external returns (bytes memory) {
        return executeMultiChecksInternal(callContracts, callDatas, callValues, checkContracts, checkValues);
    }

    /**
     * @notice Execute multiple calls in a single transaction with checks
     * @param callContracts Array of contracts to call
     * @param callDatas Array of calldatas to call
     * @param callValues Array of values to call
     * @return Return return datas array from the all the contract call
     */
    function runWithReturns(address[] calldata callContracts, bytes[] calldata callDatas, uint256[] calldata callValues)
        external
        returns (bytes[] memory)
    {
        return executeMultiWithReturnsInternal(callContracts, callDatas, callValues);
    }
}
