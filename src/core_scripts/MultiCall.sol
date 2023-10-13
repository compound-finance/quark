// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./CoreScript.sol";

contract MultiCall is CoreScript {
    /**
     * @notice Execute multiple calls in a single transaction
     * @param callContracts Array of contracts to call
     * @param callCodes Array of codes to call
     * @param callDatas Array of calldatas to call
     * @param callValues Array of values to call
     */
    function run(
        address[] calldata callContracts,
        bytes[] calldata callCodes,
        bytes[] calldata callDatas,
        uint256[] calldata callValues
    ) external {
        executeMultiInternal(callContracts, callCodes, callDatas, callValues);
    }
}
