// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

/**
 * @title Ethcall Core Script
 * @notice Core transaction script that can be used to call into another contract
 * @author Compound Labs, Inc.
 */
contract Ethcall {
    /**
     * @notice Execute a single call
     * @dev Note: Does not use a reentrancy guard, so make sure to only call into trusted contracts
     * @param callContract Contract to call
     * @param callData Encoded calldata for call
     * @param callValue Value for call
     * @return Return data from call
     */
    function run(address callContract, bytes calldata callData, uint256 callValue) external returns (bytes memory) {
        (bool success, bytes memory returnData) = callContract.call{value: callValue}(callData);
        if (!success) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }

        return returnData;
    }
}
