// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./CoreScript.sol";

contract EthCall is CoreScript {
    /**
     * @notice Execute a single call in a single transaction
     * @param callContract Contract to call
     * @param callData Calldata to call
     * @param callValue Value to call
     * @return Return data of the call in bytes
     */
    function run(address callContract, bytes calldata callData, uint256 callValue) external returns (bytes memory) {
        return executeSingleInternal(callContract, callData, callValue);
    }
}