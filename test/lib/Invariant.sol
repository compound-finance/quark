// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../src/Relayer.sol";
import "./Counter.sol";

contract CounterInvariant is Invariant {
    error CounterTooHigh(uint256 count, uint256 max);

    function check(address account, bytes calldata data) external view {
        (Counter counter, uint256 max) = abi.decode(data, (Counter, uint256));
        if (counter.number() > max) {
            revert CounterTooHigh(counter.number(), max);
        }
    }
}
