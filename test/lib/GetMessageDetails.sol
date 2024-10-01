// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

contract GetMessageDetails {
    function getMsgDetails() external payable returns (address, address, uint256) {
        return (msg.sender, address(this), msg.value);
    }
}
