// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../src/QuarkWallet.sol";
import "../../src/QuarkScript.sol";

contract SponsorTransaction is QuarkScript {
    error FeeAmountInvalid(uint256);
    error PaymentInsufficient(uint256 amount);
    error PaymentNotReceived();

    string internal constant EXPECTED_FEE_AMOUNT_SLOT = (
        "org.quark.script.SponsorTransaction.expectedFeeAmount"
    );

    string internal constant SPONSOR_BALANCE_SLOT = (
        "org.quark.script.SponsorTransaction.sponsorBalance"
    );

    function run(
        uint256 feeAmount,
        address payable wallet,
        QuarkWallet.QuarkOperation memory op,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        bool receivedPayment = false;
        // save the current wallet balance of the sponsor's EOA
        uint256 previousBalance = owner().balance;
        // feeAmount cannot be 0
        if (feeAmount == 0) {
            revert FeeAmountInvalid(feeAmount);
        }
        bytes memory result = QuarkWallet(wallet).executeQuarkOperation(op, v, r, s);
        // check for payment
        uint256 currentBalance = owner().balance;
        uint256 balanceDelta = currentBalance - previousBalance;
        // if the operation did not send any eth back to the sponsor, fail
        if (balanceDelta == 0) {
            revert PaymentNotReceived();
        }
        // if the operation did not pay enough, fail
        if (balanceDelta < feeAmount) {
            revert PaymentInsufficient(balanceDelta);
        }
        // otherwise, silence is golden.
    }
}
