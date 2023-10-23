// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "../QuarkWallet.sol";

contract Ethcall {
    /**
     * @notice Execute a single call
     * @param callContract Contract to call
     * @param callData Encoded calldata for call
     * @param callValue Value for call
     */
    function run(address callContract, bytes calldata callData, uint256 callValue) external {
        (bool success, bytes memory returnData) = callContract.call{value: callValue}(callData);
        if (!success) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }
    }
}
