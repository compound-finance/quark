// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

contract TickCounter {
    uint256 public immutable base;
    uint256 private number_;

    constructor(uint256 base_) {
        base = base_;
    }

    function number() public view returns (uint256) {
        return base + number_;
    }

    function setNumber(uint256 newNumber) public {
        number_ = newNumber;
    }

    function increment() public {
        number_++;
    }

    function increment(uint256 n) public {
        number_ += n;
    }

    function decrement(uint256 n) public returns (uint256) {
        number_ -= n;
        return number();
    }
}
