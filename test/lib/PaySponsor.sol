// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/console.sol";

contract PaySponsor {
    error InsufficientFundsForPayment();

    function runAndPay(
        address scriptTarget,
        bytes calldata scriptCalldata,
        uint paymentWei
    ) public payable returns (bytes memory) {
        // if the wallet does not have enough eth to pay, bail early
        if (paymentWei > address(this).balance) {
            revert InsufficientFundsForPayment();
        }
        (bool success, bytes memory result) = scriptTarget.call(scriptCalldata);
        if (!success) {
            // propagate the revert
            assembly {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
        // pay the sponsor before returning
        tx.origin.call{value: paymentWei}("");
        return result;
    }
}
