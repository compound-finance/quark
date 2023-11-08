// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.21;

import {QuarkWallet} from "../QuarkWallet.sol";

contract BatchExecutor {
    /// @dev Thrown when the input for a function is invalid
    error BadData();

    /**
     * @notice Execute a list of QuarkOperations via signatures
     * @param accounts A list of accounts to execute operations for
     * @param ops A list of QuarkOperations
     * @param v A list of EIP-712 signature v values
     * @param r A list of EIP-712 signature r values
     * @param s A list of EIP-712 signature s values
     * @return A list of return values from the executed operations
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
        for (uint256 i = 0; i < accounts.length; i++) {
            returnData[i] = QuarkWallet(accounts[i]).executeQuarkOperation(ops[i], v[i], r[i], s[i]);
        }
        return returnData;
    }
}
