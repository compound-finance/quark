// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";

import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkScript} from "quark-core/src/QuarkScript.sol";

contract RecurringPurchase is QuarkScript {
    using SafeERC20 for IERC20;

    error PurchaseConditionNotMet();

    /**
     * @dev Note: This script uses the following storage layout:
     *         mapping(bytes32 hashedPurchaseConfig => PurchaseState purchaseState)
     *             where hashedPurchaseConfig = keccak256(PurchaseConfig)
     */

    // TODO: Support exact input swaps
    struct SwapParamsExactOut {
        address uniswapRouter;
        address recipient;
        address tokenFrom;
        uint256 amount;
        // Maximum amount of input token to spend (revert if input amount is greater than this)
        uint256 amountInMaximum;
        uint256 deadline;
        // Path of the swap
        bytes path;
    }

    // TODO: Consider adding a purchaseWindow
    struct PurchaseConfig {
        uint40 interval;
        uint216 totalAmountToPurchase;
        SwapParamsExactOut swapParams;
    }

    struct PurchaseState {
        uint216 totalPurchased;
        uint40 nextPurchaseTime;
    }

    function purchase(PurchaseConfig calldata config) public {
        allowReplay();

        bytes32 hashedConfig = hashConfig(config);
        PurchaseState memory purchaseState;
        if (read(hashedConfig) == 0) {
            purchaseState = PurchaseState({totalPurchased: 0, nextPurchaseTime: uint40(block.timestamp)});
        } else {
            bytes memory prevState = abi.encode(read(hashedConfig));
            uint216 totalPurchased;
            uint40 nextPurchaseTime;
            // We need assembly to decode packed structs
            assembly {
                totalPurchased := mload(add(prevState, 27))
                nextPurchaseTime := mload(add(prevState, 32))
            }
            purchaseState = PurchaseState({totalPurchased: totalPurchased, nextPurchaseTime: nextPurchaseTime});
        }

        // Check conditions
        if (block.timestamp < purchaseState.nextPurchaseTime) {
            revert PurchaseConditionNotMet();
        }
        if (purchaseState.totalPurchased + config.swapParams.amount > config.totalAmountToPurchase) {
            revert PurchaseConditionNotMet();
        }

        SwapParamsExactOut memory swapParams = config.swapParams;
        IERC20(swapParams.tokenFrom).forceApprove(swapParams.uniswapRouter, swapParams.amountInMaximum);
        ISwapRouter(swapParams.uniswapRouter).exactOutput(
            ISwapRouter.ExactOutputParams({
                path: swapParams.path,
                recipient: swapParams.recipient,
                deadline: swapParams.deadline,
                amountOut: swapParams.amount,
                amountInMaximum: swapParams.amountInMaximum
            })
        );

        PurchaseState memory newPurchaseState = PurchaseState({
            totalPurchased: purchaseState.totalPurchased + uint216(config.swapParams.amount),
            // TODO: or should it be purchaseState.nextPurchaseTime + config.interval?
            nextPurchaseTime: purchaseState.nextPurchaseTime + config.interval
        });

        // Write new PurchaseState to storage
        write(
            hashedConfig, bytes32(abi.encodePacked(newPurchaseState.totalPurchased, newPurchaseState.nextPurchaseTime))
        );
    }

    function cancel() external {
        // Not explicitly clearing the nonce just cancels the replayable txn
    }

    function hashConfig(PurchaseConfig calldata config) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                config.interval,
                config.totalAmountToPurchase,
                abi.encodePacked(
                    config.swapParams.uniswapRouter,
                    config.swapParams.recipient,
                    config.swapParams.tokenFrom,
                    config.swapParams.amount,
                    config.swapParams.amountInMaximum,
                    config.swapParams.deadline,
                    config.swapParams.path
                )
            )
        );
    }
}
