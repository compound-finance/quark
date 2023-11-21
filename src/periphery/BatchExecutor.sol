// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {QuarkWallet} from "../QuarkWallet.sol";

/**
 * @title Batch Executor for Quark Operations
 * @notice An entry point contract that enables a submitter to submit multiple Quark Operations for different
 *         accounts in a single transaction
 * @author Compound Labs, Inc.
 */
contract BatchExecutor {
    /// @dev Thrown when the input for a function is invalid
    error BadData();

    /**
     * @notice Execute a list of QuarkOperations via signatures
     * @param accounts List of accounts to execute operations for
     * @param ops List of QuarkOperations
     * @param v List of EIP-712 signature v values
     * @param r List of EIP-712 signature r values
     * @param s List of EIP-712 signature s values
     * @return List of return values from the executed operations
     */
    function batchExecuteOperations(
        address[] calldata accounts,
        QuarkWallet.QuarkOperation[] calldata ops,
        uint8[] calldata v,
        bytes32[] calldata r,
        bytes32[] calldata s
    ) external returns (bytes[] memory) {
        if (
            accounts.length != ops.length || accounts.length != v.length || accounts.length != r.length
                || accounts.length != s.length
        ) {
            revert BadData();
        }

        bytes[] memory returnData = new bytes[](accounts.length);
        for (uint256 i = 0; i < accounts.length;) {
            returnData[i] = QuarkWallet(payable(accounts[i])).executeQuarkOperation(ops[i], v[i], r[i], s[i]);
            unchecked {
                ++i;
            }
        }
        return returnData;
    }
}
