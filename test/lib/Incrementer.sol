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

    // TODO: Uncomment when replay tokens are supported
    // function incrementCounterReplayable(Counter counter) public {
    //     incrementCounter(counter);
    //     QuarkWallet(payable(address(this))).nonceManager().clearNonce();
    // }

    fallback() external {
        // Counter
        address counter = 0xF62849F9A0B5Bf2913b396098F7c7019b51A820a;
        incrementCounter(Counter(counter));
    }
}
