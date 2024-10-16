// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import "quark-core/src/QuarkScript.sol";
import "quark-core/src/QuarkWallet.sol";

interface IComeback {
    function request() external returns (uint256);
}

contract Comebacker {
    function comeback() public returns (uint256) {
        return IComeback(msg.sender).request() + 1;
    }
}

contract AllowCallbacks is QuarkScript {
    function run() public returns (uint256) {
        allowCallback();
        return new Comebacker().comeback() * 2;
    }

    function runAllowThenClear() public returns (uint256) {
        allowCallback();
        disallowCallback();
        return new Comebacker().comeback() * 2;
    }

    function runWithoutAllow() public returns (uint256) {
        return new Comebacker().comeback() * 2;
    }

    function request() external view returns (uint256) {
        return 100 + getActiveReplayCount();
    }
}
