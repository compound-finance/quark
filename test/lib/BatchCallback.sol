// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import "quark-core/src/QuarkScript.sol";
import "quark-core/src/QuarkWallet.sol";

contract BatchSend {
    function submitTwo(
        QuarkWallet wallet1,
        QuarkWallet.QuarkOperation memory op1,
        bytes memory signature1,
        QuarkWallet wallet2,
        QuarkWallet.QuarkOperation memory op2,
        bytes memory signature2
    ) public returns (uint256) {
        wallet1.executeQuarkOperation(op1, signature1);
        wallet2.executeQuarkOperation(op2, signature2);
        return IncrementByCallback(address(wallet1)).number();
    }
}

contract IncrementByCallback is QuarkScript {
    uint256 public number;

    function run() public {
        allowCallback();
        IncrementByCallback(address(this)).increment();
        IncrementByCallback(address(this)).increment();
    }

    function increment() external {
        number++;
    }
}

contract CallIncrement is QuarkScript {
    function run(address wallet) public {
        IncrementByCallback(wallet).increment();
    }
}
