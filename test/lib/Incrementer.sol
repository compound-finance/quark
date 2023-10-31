// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "./Counter.sol";

import "../../src/QuarkWallet.sol";

contract Incrementer {
    function incrementCounter(Counter counter) public {
        Counter(counter).increment();
        Counter(counter).increment();
        Counter(counter).increment();
    }

    function incrementCounterReplayable(Counter counter) public {
        incrementCounter(counter);
        QuarkWallet(payable(msg.sender)).stateManager().clearNonce();
    }

    fallback() external {
        // Counter
        address counter = 0xF62849F9A0B5Bf2913b396098F7c7019b51A820a;
        incrementCounter(Counter(counter));
    }
}
