// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Counter.sol";

contract Incrementer {
  fallback() external {

    // Counter
    address counter = 0xF62849F9A0B5Bf2913b396098F7c7019b51A820a;
    // Relayer, as hard-coded in the script
    // address counter = 0x2e234DAe75C793f67A35089C9d99245E1C58470b;
    Counter(counter).increment();
    Counter(counter).increment();
    Counter(counter).increment();
  }
}
