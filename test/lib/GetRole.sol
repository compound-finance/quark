// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.21;

import "../../src/QuarkScript.sol";
import "../../src/QuarkWallet.sol";

contract GetRole is QuarkScript {
    function getSigner() external view returns (address) {
        return QuarkWallet(address(this)).signer();
    }

    function getExecutor() external view returns (address) {
        return QuarkWallet(address(this)).executor();
    }
}
