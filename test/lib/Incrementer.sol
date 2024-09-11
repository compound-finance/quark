// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "test/lib/Counter.sol";

import "quark-core/src/QuarkWallet.sol";

contract Incrementer {
    function incrementCounter(Counter counter) public {
        Counter(counter).increment();
        Counter(counter).increment();
        Counter(counter).increment();
    }

    function incrementCounter2(Counter counter) public {
        Counter(counter).increment();
        Counter(counter).increment();
        Counter(counter).increment();
        Counter(counter).increment();
    }

    fallback() external {
        // Counter
        address counter = 0xF62849F9A0B5Bf2913b396098F7c7019b51A820a;
        incrementCounter(Counter(counter));
    }
}

contract IncrementerBySix {
    function incrementCounter(Counter counter) public {
        Counter(counter).increment();
        Counter(counter).increment();
        Counter(counter).increment();
        Counter(counter).increment();
        Counter(counter).increment();
        Counter(counter).increment();
    }
}
