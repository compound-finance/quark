// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

contract ReentrantTransfer {
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
}
