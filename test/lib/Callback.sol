// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Counter.sol";

contract Callback {
    address constant public counter = address(0xF62849F9A0B5Bf2913b396098F7c7019b51A820a);

    function counterCallback(uint256) external {
      Counter(counter).increment(Counter(counter).number() * 10);
    }

    fallback() external {
      Counter(counter).incrementCallback();
    }
}
