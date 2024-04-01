// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "quark-core/src/QuarkWallet.sol";
import "quark-core/src/QuarkScript.sol";

import {TransferActions} from "test/lib/Transfer.sol";

contract EvilReceiver {
    enum AttackType {
        REINVOKE_TRANSFER,
        STOLEN_SIGNATURE
    }

    struct ReentryAttack {
        AttackType attackType;
        address destination;
        uint256 amount;
        uint256 maxCalls;
    }

    struct StolenSignature {
        QuarkWallet.QuarkOperation op;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    uint256 public loop = 1;
    uint256 public count = 0;
    ReentryAttack public attack;
    StolenSignature public stolenSignature;
    address public targetTokenAddress;

    function setAttack(ReentryAttack calldata t) public {
        attack = t;
    }

    function stealSignature(StolenSignature calldata t) public {
        stolenSignature = t;
    }

    function setTargetTokenAddress(address t) public {
        targetTokenAddress = t;
    }

    function startAttack(bool isERC20, address from, address to, uint256 amount) public {
        if (count < attack.maxCalls) {
            count++;
            if (attack.attackType == AttackType.REINVOKE_TRANSFER) {
                // Simply cast the address to Terminal script and call the Transfer function
                if (isERC20) {
                    TransferActions(from).transferERC20Token(targetTokenAddress, to, amount);
                } else {
                    TransferActions(from).transferNativeToken(attack.destination, attack.amount);
                }
            }

            if (attack.attackType == AttackType.STOLEN_SIGNATURE) {
                QuarkWallet(payable(msg.sender)).executeQuarkOperation(
                    stolenSignature.op, stolenSignature.v, stolenSignature.r, stolenSignature.s
                );
            }
        }
    }

    function tokensReceived(
        address, /* operator */
        address from,
        address, /* to */
        uint256, /* amount */
        bytes calldata,
        bytes calldata
    ) external {
        startAttack(true, from, attack.destination, attack.amount);
    }

    receive() external payable {
        startAttack(false, msg.sender, attack.destination, attack.amount);
    }
}
