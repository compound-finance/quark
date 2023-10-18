// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../QuarkScript.sol";
import "../QuarkWallet.sol";

contract CoreScript is QuarkScript {
    error InvalidInput();
    error CallError(address callContract, bytes callData, uint256 callValue, bytes err);
    error MultiCallError(uint256 n, address callContract, bytes callData, uint256 callValue, bytes err);
    error MultiCallCheckError(uint256 n, address callContract, bytes callData, uint256 callValue, bytes data, address checkContract, bytes checkData, bytes err);
    /**
     * @dev Execute multiple calls in a single transaction
     * @param callContracts Array of contracts to call
     * @param callDatas Array of calldatas to call
     * @param callValues Array of values to call
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
     * @dev Execute multiple calls in a single transaction with returns (more gasy)
     * @param callContracts Array of contracts to call
     * @param callDatas Array of calldatas to call
     * @param callValues Array of values to call
     * @return Array of return data of the calls in bytes
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
     * @dev Execute multiple calls in a single transaction with returns and checks
     * @param callContracts Array of contracts to call
     * @param callDatas Array of calldatas to call
     * @param callValues Array of values to call
     * @param checkContracts Array of contracts to call to check the return data
     * @param checkValues Array of values for check contracts to check
     * @return bytes from the last call
     */
    function executeMultiChecksInternal(
        address[] memory callContracts,
        bytes[] memory callDatas,
        uint256[] memory callValues,
        address[] memory checkContracts,
        bytes[] memory checkValues
    ) internal returns (bytes memory) {
        if (
            callContracts.length != callDatas.length || callContracts.length != callValues.length
                || checkContracts.length != callContracts.length || checkContracts.length != checkValues.length
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
                    ? abi.encodeWithSignature("check(bytes,bytes)", data, checkValues[i])
                    : abi.encodeWithSignature("check(bytes)", data);
                (bool checkSuccess, bytes memory checkReturnData) = checkContracts[i].call(encodedCheckCall);
                if (!checkSuccess) {
                    revert MultiCallCheckError(
                        i, callContracts[i], callDatas[i], callValues[i], data, checkContracts[i], checkValues[i], checkReturnData
                    );
                }
            }
        }

        return data;
    }

    /**
     * @dev Execute a single call in a single transaction
     * @param callContract Contract to call (contract address, can't have both callContract and callCode)
     * @param callData Calldata to call
     * @param callValue Value to call
     * @return return value from the executed operation in bytes
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
