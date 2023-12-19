// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "quark-core-scripts/src/lib/SelfdestructScanner.sol";

/**
 * @title Multicall Core Script
 * @notice Core transaction script that can be used to bundle multiple delegatecalls into a single operation
 * @author Compound Labs, Inc.
 */
contract Multicall is SelfdestructScanner {
    error InvalidInput();
    error MulticallError(uint256 callIndex, address callContract, bytes err);
    error SelfdestructableScript();
    /**
     * @notice Execute multiple delegatecalls to contracts in a single transaction
     * @param callContracts Array of contracts to call
     * @param callDatas Array of encoded calldata for each call
     * @return Array of return data from each call
     */

    function run(address[] calldata callContracts, bytes[] calldata callDatas) external returns (bytes[] memory) {
        if (callContracts.length != callDatas.length) {
            revert InvalidInput();
        }

        bytes[] memory returnDatas = new bytes[](callContracts.length);
        for (uint256 i = 0; i < callContracts.length;) {
            if (hasSelfdestructYul(callContracts[i].code)) {
                revert SelfdestructableScript();
            }

            (bool success, bytes memory returnData) = callContracts[i].delegatecall(callDatas[i]);
            if (!success) {
                revert MulticallError(i, callContracts[i], returnData);
            }
            returnDatas[i] = returnData;

            unchecked {
                ++i;
            }
        }

        return returnDatas;
    }
}
