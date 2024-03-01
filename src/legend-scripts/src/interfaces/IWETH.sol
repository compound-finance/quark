// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}