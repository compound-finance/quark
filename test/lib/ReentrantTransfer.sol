// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

contract ReentrantTransfer {
    using SafeERC20 for IERC20;

    error TransferFailed(bytes data);

    /**
     * @notice Transfer native token (i.e. ETH) without re-entrancy guards
     * @param recipient The recipient address
     * @param amount The amount to transfer
     */
    function transferNativeToken(address recipient, uint256 amount) external {
        // Transfer without using re-entrancy guards
        (bool success, bytes memory data) = payable(recipient).call{value: amount}("");
        if (!success) {
            revert TransferFailed(data);
        }
    }

    /**
     * @notice Transfer ERC20 token without re-entrancy guards
     * @param token The token address
     * @param recipient The recipient address
     * @param amount The amount to transfer
     */
    function transferERC20Token(address token, address recipient, uint256 amount) external {
        IERC20(token).safeTransfer(recipient, amount);
    }
}
