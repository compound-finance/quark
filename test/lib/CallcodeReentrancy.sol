// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "forge-std/console.sol";

import "quark-core/src/QuarkScript.sol";

interface CallbackReceiver {
    function callMeBack(address, bytes calldata, uint256) external payable returns (bytes memory);
    function receiveCallback() external;
}

contract ExploitableScript is QuarkScript, CallbackReceiver {
    // we expect a callback, but we do not guard gainst re-entrancy, allowing the caller to steal funds
    function callMeBack(address target, bytes calldata call, uint256 fee) external payable returns (bytes memory) {
        allowCallback();
        (bool success, bytes memory result) = target.call{value: fee}(call);
        if (!success) {
            assembly {
                revert(add(result, 0x20), mload(result))
            }
        }
        return result;
    }

    // one could imagine that we are repaying a flash loan, for example, here
    function receiveCallback() external {}
}

contract ProtectedScript is QuarkScript, CallbackReceiver {
    // we expect a callback, guarding against re-entrancy, so we only pay the target once
    function callMeBack(address target, bytes calldata call, uint256 fee) external payable returns (bytes memory) {
        require(msg.sender == address(this));
        allowCallback();
        (bool success, bytes memory result) = target.call{value: fee}(call);
        if (!success) {
            assembly {
                revert(add(result, 0x20), mload(result))
            }
        }
        return result;
    }

    // one could imagine that we are repaying a flash loan, for example, here
    function receiveCallback() external {}
}

contract CallbackCaller {
    function doubleDip(bool dipped) external payable {
        if (!dipped) {
            CallbackReceiver(msg.sender).callMeBack{value: msg.value}(
                address(this), abi.encodeCall(CallbackCaller.doubleDip, (true)), msg.value * 2
            );
        } else {
            CallbackReceiver(msg.sender).receiveCallback();
        }
    }

    function beGood() external payable {
        CallbackReceiver(msg.sender).receiveCallback();
    }
}
