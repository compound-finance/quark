// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../QuarkScript.sol";
import "../CodeJar.sol";

contract DelegateMulticall is QuarkScript {
    error InvalidInput();
    error CallError(uint256 n, address callContract, bytes callData, uint256 callValue, bytes err);
    error DelegateCallError(uint256 n, bytes callCode, bytes callData, uint256 callValue, bytes err);

    function run(address[] calldata callContracts, bytes[] calldata callCodes, bytes[] calldata callDatas, uint256[] calldata callValues) external onlyRelayer returns (bytes memory) {
        if (callContracts.length != callDatas.length || callContracts.length != callCodes.length || callContracts.length != callValues.length) {
            revert InvalidInput();
        }

        for (uint256 i = 0; i < callContracts.length; i++) {
            bool isExec;
            address callContract = callContracts[i];
            bytes memory callCode = callCodes[i];
            bool isCallContract = callContract != address(0);
            bool isCallCode = callCode.length > 0;
            if (isCallContract == isCallCode) {
                revert InvalidInput();
            }
            bytes memory callData = callDatas[i];
            uint256 callValue = callValues[i];

            if (isCallCode) {
                if (callValue != 0) {
                    revert InvalidInput();
                }
                CodeJar codeJar = relayer().codeJar();
                address codeAddress = codeJar.saveCode(callCode);
                (bool success, bytes memory returnData) = codeAddress.delegatecall(callData);
                if (!success) {
                    revert DelegateCallError(i, callCode, callData, callValue, returnData);
                }
            } else {
                if (callContract == 0x906f4bD1940737091f18247eAa870D928A85b9Ce) { // keccak("tx.origin")[0:20]
                    callContract = tx.origin;
                }
                (bool success, bytes memory returnData) = callContract.call{value: callValue}(callData);
                if (!success) {
                    revert CallError(i, callContract, callData, callValue, returnData);
                }
            }
        }
        return abi.encode(hex"");
    }

    // Allow unwrapping Ether
    receive() external payable {}
}
