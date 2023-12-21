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
     */
    function batchExecuteOperations(
        OperationParams[] calldata ops
    ) external {
        for (uint256 i = 0; i < ops.length;) {
                executeOperation(ops[i]);
                unchecked {
                    ++i;
            }
        }
    }

    /// @notice Execute a single QuarkOperation via signature
    function executeOperation(OperationParams memory op)
        internal
    {
        bytes memory data = abi.encodeWithSelector(
            QuarkWallet.executeQuarkOperation.selector,
            op.op, op.v, op.r, op.s
        );
        // We purposely ignore success and return values since the BatchExecutor will most likely be called by an EOA
        op.account.call{gas: op.gasLimit}(data);
    }
}
