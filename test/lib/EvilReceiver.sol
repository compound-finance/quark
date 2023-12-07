// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "../../src/QuarkWallet.sol";
import "../../src/QuarkScript.sol";
import "../../src/terminal_scripts/TerminalScript.sol";

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

    function tokensReceived(address, address from, address to, uint256 amount, bytes calldata, bytes calldata)
        external
    {
        if (count < attack.maxCalls) {
            count++;
            if (attack.attackType == AttackType.REINVOKE_TRANSFER) {
                // Simply cast the address to Terminal script and call the Transfer function
                TransferActions(from).transferERC20Token(targetTokenAddress, to, amount);
            }

            if (attack.attackType == AttackType.STOLEN_SIGNATURE) {
                QuarkWallet(payable(from)).executeQuarkOperation(
                    stolenSignature.op, stolenSignature.v, stolenSignature.r, stolenSignature.s
                );
            }
        }
    }

    receive() external payable {
        if (count < attack.maxCalls) {
            count++;
            if (attack.attackType == AttackType.REINVOKE_TRANSFER) {
                // Simply cast the address to Terminal script and call the Transfer function
                TransferActions(msg.sender).transferNativeToken(attack.destination, attack.amount);
            }

            if (attack.attackType == AttackType.STOLEN_SIGNATURE) {
                QuarkWallet(payable(msg.sender)).executeQuarkOperation(
                    stolenSignature.op, stolenSignature.v, stolenSignature.r, stolenSignature.s
                );
            }
        }
    }
}
