// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";

/**
 * @title Batch Executor for Quark Operations
 * @notice An entry point contract that enables a submitter to submit multiple Quark Operations for different
 *         accounts in a single transaction
 * @author Compound Labs, Inc.
 */
contract BatchExecutor {
    error BatchExecutionError(uint256 opsIndex, bytes err);

    /// @notice The parameters used for processing a QuarkOperation
    struct OperationParams {
        address account;
        QuarkWallet.QuarkOperation op;
        uint8 v;
        bytes32 r;
        bytes32 s;
        uint256 gasLimit;
    }

    /**
     * @notice Execute a list of QuarkOperations via signatures
     * @param ops List of QuarkOperations to execute via signature
     * @param allowPartialFailures Whether or not to allow partial failures when any of the calls revert
     */
    function batchExecuteOperations(OperationParams[] calldata ops, bool allowPartialFailures) external {
        for (uint256 i = 0; i < ops.length; ++i) {
            (bool success, bytes memory returnData) = executeOperation(ops[i]);
            if (!allowPartialFailures && !success) {
                revert BatchExecutionError(i, returnData);
            }
        }
    }

    /**
     * @notice Execute a single QuarkOperation via signature
     * @param op Quark Operation parameters to execute via signature
     * @return Success and return value from the executed operation
     */
    function executeOperation(OperationParams memory op) internal returns (bool, bytes memory) {
        bytes memory data = abi.encodeWithSelector(QuarkWallet.executeQuarkOperation.selector, op.op, op.v, op.r, op.s);
        // We purposely ignore success and return values since the BatchExecutor will most likely be called by an EOA
        // Lower-level call is used to avoid reverting on failure
        (bool success, bytes memory retData) = op.account.call{gas: op.gasLimit}(data);
        return (success, retData);
    }
}
