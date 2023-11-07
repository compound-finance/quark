// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "../../src/QuarkScript.sol";
import "../../src/QuarkWallet.sol";

contract GetRole is QuarkScript {
    function getSigner() external returns (address) {
        return QuarkWallet(address(this)).signer();
    }

    function getExecutor() external returns (address) {
        return QuarkWallet(address(this)).executor();
    }
}
