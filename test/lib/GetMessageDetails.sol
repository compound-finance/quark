// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

contract GetMessageDetails {
    function getMsgSenderAndValue() external payable returns (address, uint256) {
        return (msg.sender, msg.value);
    }
}
