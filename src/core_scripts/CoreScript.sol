// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../QuarkScript.sol";
import "../QuarkWallet.sol";

contract CoreScript is QuarkScript {
    error CallError(address callContract, bytes callData, uint256 callValue, bytes err);
    error InvalidInput();
    error MultiCallError(uint256 callIndex, address callContract, bytes callData, uint256 callValue, bytes err);
    error MultiCallCheckError(
        uint256 callIndex,
        address callContract,
        bytes callData,
        uint256 callValue,
        bytes data,
        address checkContract,
        bytes4 checkSelector,
        bytes checkData,
        bytes err
    );

    /**
     * @dev Execute multiple calls in a single transaction
     */
    function executeMultiInternal(address[] memory callContracts, bytes[] memory callDatas, uint256[] memory callValues)
        internal
    {
        if (callContracts.length != callDatas.length || callContracts.length != callValues.length) {
            revert InvalidInput();
        }

        for (uint256 i = 0; i < callContracts.length; i++) {
            (bool success, bytes memory returnData) = callContracts[i].call{value: callValues[i]}(callDatas[i]);
            if (!success) {
                revert MultiCallError(i, callContracts[i], callDatas[i], callValues[i], returnData);
            }
        }
    }

    /**
     * @dev Execute multiple calls in a single transaction and return results (more gassy)
     */
    function executeMultiWithReturnsInternal(
        address[] memory callContracts,
        bytes[] memory callDatas,
        uint256[] memory callValues
    ) internal returns (bytes[] memory) {
        if (callContracts.length != callDatas.length || callContracts.length != callValues.length) {
            revert InvalidInput();
        }

        bytes[] memory returnDatas = new bytes[](callContracts.length);
        for (uint256 i = 0; i < callContracts.length; i++) {
            (bool success, bytes memory returnData) = callContracts[i].call{value: callValues[i]}(callDatas[i]);
            if (!success) {
                revert MultiCallError(i, callContracts[i], callDatas[i], callValues[i], returnData);
            }
            returnDatas[i] = returnData;
        }

        return returnDatas;
    }

    /**
     * @dev Execute multiple calls in a single transaction with checks, returning the last result
     */
    function executeMultiChecksInternal(
        address[] memory callContracts,
        bytes[] memory callDatas,
        uint256[] memory callValues,
        address[] memory checkContracts,
        bytes4[] memory checkSelectors,
        bytes[] memory checkValues
    ) internal returns (bytes memory) {
        if (
            callContracts.length != callDatas.length || callContracts.length != callValues.length
                || callContracts.length != checkContracts.length || callContracts.length != checkValues.length
                || callContracts.length != checkSelectors.length
        ) {
            revert InvalidInput();
        }

        bytes memory data;
        for (uint256 i = 0; i < callContracts.length; i++) {
            (bool success, bytes memory returnData) = callContracts[i].call{value: callValues[i]}(callDatas[i]);
            if (!success) {
                revert MultiCallError(i, callContracts[i], callDatas[i], callValues[i], returnData);
            }

            data = returnData;
            if (checkContracts[i] != address(0)) {
                bytes memory encodedCheckCall = checkValues[i].length > 0
                    ? abi.encodeWithSelector(checkSelectors[i], data, checkValues[i])
                    : abi.encodeWithSelector(checkSelectors[i], data);
                (bool checkSuccess, bytes memory checkReturnData) = checkContracts[i].call(encodedCheckCall);
                if (!checkSuccess) {
                    revert MultiCallCheckError(
                        i,
                        callContracts[i],
                        callDatas[i],
                        callValues[i],
                        data,
                        checkContracts[i],
                        checkSelectors[i],
                        checkValues[i],
                        checkReturnData
                    );
                }
            }
        }

        return data;
    }

    /**
     * @dev Execute a single call in a single transaction and return the result
     */
    function executeSingleInternal(address callContract, bytes memory callData, uint256 callValue)
        internal
        returns (bytes memory)
    {
        (bool success, bytes memory returnData) = callContract.call(callData);
        if (!success) {
            revert CallError(callContract, callData, callValue, returnData);
        }

        return returnData;
    }

    // Allow unwrapping Ether
    receive() external payable {}
}
