// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../QuarkScript.sol";
import "../QuarkWallet.sol";

contract CoreScript is QuarkScript {
    error InvalidInput();
    error CallError(address callContract, bytes callData, uint256 callValue, bytes err);
    error MultiCallError(uint256 n, address callContract, bytes callData, uint256 callValue, bytes err);
    error DelegateCallError(bytes callCode, bytes callData, uint256 callValue, bytes err);
    error MultiDelegateCallError(uint256 n, bytes callCode, bytes callData, uint256 callValue, bytes err);

    /**
     * @dev Execute multiple calls in a single transaction
     * @param callContracts Array of contracts to call
     * @param callCodes Array of codes to call
     * @param callDatas Array of calldatas to call
     * @param callValues Array of values to call
     */
    function executeMultiInternal(
        address[] memory callContracts,
        bytes[] memory callCodes,
        bytes[] memory callDatas,
        uint256[] memory callValues
    ) internal {
        if (
            callContracts.length != callDatas.length || callContracts.length != callCodes.length
                || callContracts.length != callValues.length
        ) {
            revert InvalidInput();
        }

        for (uint256 i = 0; i < callContracts.length; i++) {
            bool isCallContract = callContracts[i] != address(0);
            bool isCallCode = callCodes[i].length != 0;
            if (isCallCode == isCallContract) {
                revert InvalidInput();
            }

            if (isCallCode) {
                if (callValues[i] != 0) {
                    revert InvalidInput();
                }

                address codeAddress = QuarkWallet(msg.sender).codeJar().saveCode(callCodes[i]);
                (bool success, bytes memory returnData) = codeAddress.delegatecall(callDatas[i]);
                if (!success) {
                    revert MultiDelegateCallError(i, callCodes[i], callDatas[i], callValues[i], returnData);
                }
            }

            if (isCallContract) {
                (bool success, bytes memory returnData) = callContracts[i].call{value: callValues[i]}(callDatas[i]);
                if (!success) {
                    revert MultiCallError(i, callContracts[i], callDatas[i], callValues[i], returnData);
                }
            }
        }
    }

    /**
     * @dev Execute a single call in a single transaction
     * @param callContract Contract to call (contract address, can't have both callContract and callCode)
     * @param callCode Code to call (arbitrary bytecode that will be saved into the code jar, can't have both callContract and callCode)
     * @param callData Calldata to call
     * @param callValue Value to call
     * @return return value from the executed operation in bytes
     */
    function executeSingleInternal(
        address callContract,
        bytes memory callCode,
        bytes memory callData,
        uint256 callValue
    ) internal returns (bytes memory) {
        bool isCallContract = callContract != address(0);
        bool isCallCode = callCode.length != 0;
        if (isCallCode == isCallContract) {
            revert InvalidInput();
        }

        if (isCallCode) {
            if (callValue != 0) {
                revert InvalidInput();
            }

            address codeAddress = QuarkWallet(msg.sender).codeJar().saveCode(callCode);
            (bool success, bytes memory returnData) = codeAddress.delegatecall(callData);
            if (!success) {
                revert DelegateCallError(callCode, callData, callValue, returnData);
            }

            return returnData;
        }

        if (isCallContract) {
            (bool success, bytes memory returnData) = callContract.call(callData);
            if (!success) {
                revert CallError(callContract, callData, callValue, returnData);
            }

            return returnData;
        }

        return hex""; // return empty bytes, should not reach here
    }

    // Allow unwrapping Ether
    receive() external payable {}
}
