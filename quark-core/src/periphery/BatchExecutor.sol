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
    /// @notice The parameters used for processing a Quark operation
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
     * @return List of return values from the executed operations
     */
    function batchExecuteOperations(
        OperationParams[] calldata ops
    ) external returns (bool[] memory, bytes[] memory) {
        bool[] memory successes = new bool[](ops.length);
        bytes[] memory returnData = new bytes[](ops.length);
        for (uint256 i = 0; i < ops.length;) {
                (successes[i], returnData[i]) = executeOperation(ops[i]);
                unchecked {
                    ++i;
            }
        }
        return (successes, returnData);
    }

    /// @notice Execute a single QuarkOperations via signature
    function executeOperation(OperationParams memory op)
        internal returns (bool, bytes memory)
    {
        bytes memory data = abi.encodeWithSelector(
            QuarkWallet.executeQuarkOperation.selector,
            op.op, op.v, op.r, op.s
        );

        (bool success, bytes memory retData) = op.account.call{gas: op.gasLimit}(data);
        return (success, retData);
    }
}
