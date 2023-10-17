// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../src/QuarkWallet.sol";
import "../../src/QuarkScript.sol";

contract SponsorTransaction is QuarkScript {
    error FeeAmountInvalid(uint);
    error PaymentAlreadyReceived();
    error PaymentInsufficient(uint amount);
    error PaymentNotReceived();
    error ReentrantCall();

    string internal constant RECEIVED_PAYMENT_SLOT = (
        "org.quark.script.SponsorTransaction.receivedPayment"
    );

    string internal constant EXPECTED_FEE_AMOUNT_SLOT = (
        "org.quark.script.SponsorTransaction.expectedFeeAmount"
    );

    string internal constant SPONSOR_ADDRESS_SLOT = (
        "org.quark.script.SponsorTransaction.sponsorAddress"
    );

    function run(
        uint feeAmount,
        address payable wallet,
        QuarkWallet.QuarkOperation memory op,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        bool receivedPayment = sloadBool(RECEIVED_PAYMENT_SLOT);
        // assert that receivedPayment must be false on entry
        if (receivedPayment) {
            revert ReentrantCall();
        }
        // feeAmount cannot be 0
        if (feeAmount == 0) {
            revert FeeAmountInvalid(feeAmount);
        }
        sstoreU256(EXPECTED_FEE_AMOUNT_SLOT, feeAmount);
        bytes memory result = QuarkWallet(wallet).executeQuarkOperation(op, v, r, s);
        // reload receivedPayment
        receivedPayment = sloadBool(RECEIVED_PAYMENT_SLOT);
        // if the operation did not send any eth back to the sponsor, fail
        if (!receivedPayment) {
            revert PaymentNotReceived();
        }
        // otherwise, we're good, and we should reset receivedPayment to false
        sstoreBool(RECEIVED_PAYMENT_SLOT, false);
    }

    receive() external payable {
        bool receivedPayment = sloadBool(RECEIVED_PAYMENT_SLOT);
        if (receivedPayment) {
            revert PaymentAlreadyReceived();
        }
        uint feeAmount = sloadU256(EXPECTED_FEE_AMOUNT_SLOT);
        if (msg.value >= feeAmount) {
            sstoreBool(RECEIVED_PAYMENT_SLOT, true);
        } else {
            revert PaymentInsufficient(msg.value);
        }
    }

    fallback() external payable {}
}
