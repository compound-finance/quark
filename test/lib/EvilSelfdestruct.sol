// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

contract EvilSelfdestruct {
    function attack() external {
        selfdestruct(payable(msg.sender));
    }
}
