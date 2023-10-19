// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./CoreScript.sol";

contract Ethcall is CoreScript {
    error InvalidInput();
    error CallError(address callContract, bytes callData, uint256 callValue, bytes err);

    function run(address callContract, bytes calldata callCode, bytes calldata callData, uint256 callValue)
        external
        returns (bytes memory)
    {
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
        } else if (isCallContract) {
            (bool success, bytes memory returnData) = callContract.call{value: callValue}(callData);
            if (!success) {
                revert CallError(callContract, callData, callValue, returnData);
            }

            return returnData;
        } else {
            revert InvalidInput();
        }
    }
}
