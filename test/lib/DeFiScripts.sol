// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";

import {IComet} from "test/quark-core-scripts/interfaces/IComet.sol";

contract CometSupplyActions {
    using SafeERC20 for IERC20;

    error InvalidInput();

    /**
     *   @notice Supply an asset to Comet
     *   @param comet The Comet address
     *   @param asset The asset address
     *   @param amount The amount to supply
     */
    function supply(address comet, address asset, uint256 amount) external {
        IERC20(asset).forceApprove(comet, amount);
        IComet(comet).supply(asset, amount);
    }

    /**
     * @notice Supply an asset to Comet to a specific address
     * @param comet The Comet address
     * @param to The recipient address
     * @param asset The asset address
     * @param amount The amount to supply
     */
    function supplyTo(address comet, address to, address asset, uint256 amount) external {
        IERC20(asset).forceApprove(comet, amount);
        IComet(comet).supplyTo(to, asset, amount);
    }

    /**
     *   @notice Supply an asset to Comet from one address to another address
     *   @param comet The Comet address
     *   @param from The from address
     *   @param to The to address
     *   @param asset The asset address
     *   @param amount The amount to supply
     */
    function supplyFrom(address comet, address from, address to, address asset, uint256 amount) external {
        IComet(comet).supplyFrom(from, to, asset, amount);
    }

    /**
     * @notice Supply multiple assets to Comet
     * @param comet The Comet address
     * @param assets The assets to supply
     * @param amounts The amounts of each asset to supply
     */
    function supplyMultipleAssets(address comet, address[] calldata assets, uint256[] calldata amounts) external {
        if (assets.length != amounts.length) {
            revert InvalidInput();
        }

        for (uint256 i = 0; i < assets.length;) {
            IERC20(assets[i]).forceApprove(comet, amounts[i]);
            IComet(comet).supply(assets[i], amounts[i]);
            unchecked {
                ++i;
            }
        }
    }
}

contract CometWithdrawActions {
    using SafeERC20 for IERC20;

    error InvalidInput();

    /**
     *  @notice Withdraw an asset from Comet
     *  @param comet The Comet address
     *  @param asset The asset address
     *  @param amount The amount to withdraw
     */
    function withdraw(address comet, address asset, uint256 amount) external {
        IComet(comet).withdraw(asset, amount);
    }

    /**
     * @notice Withdraw an asset from Comet to a specific address
     * @param comet The Comet address
     * @param to The recipient address
     * @param asset The asset address
     * @param amount The amount to withdraw
     */
    function withdrawTo(address comet, address to, address asset, uint256 amount) external {
        IComet(comet).withdrawTo(to, asset, amount);
    }

    /**
     *   @notice Withdraw an asset from Comet from one address to another address
     *   @param comet The Comet address
     *   @param from The from address
     *   @param to The to address
     *   @param asset The asset address
     *   @param amount The amount to withdraw
     */
    function withdrawFrom(address comet, address from, address to, address asset, uint256 amount) external {
        IComet(comet).withdrawFrom(from, to, asset, amount);
    }

    /**
     * @notice Withdraw multiple assets from Comet
     * @param comet The Comet address
     * @param assets The assets to withdraw
     * @param amounts The amounts of each asset to withdraw
     */
    function withdrawMultipleAssets(address comet, address[] calldata assets, uint256[] calldata amounts) external {
        if (assets.length != amounts.length) {
            revert InvalidInput();
        }

        for (uint256 i = 0; i < assets.length;) {
            IComet(comet).withdraw(assets[i], amounts[i]);
            unchecked {
                ++i;
            }
        }
    }
}

contract UniswapSwapActions {
    using SafeERC20 for IERC20;

    struct SwapParamsExactIn {
        address uniswapRouter;
        address recipient;
        address tokenFrom;
        uint256 amount;
        // Minimum amount of target token to receive (revert if return amount is less than this)
        uint256 amountOutMinimum;
        uint256 deadline;
        // Path of the swap
        bytes path;
    }

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

    /**
     * @notice Swap token on Uniswap with Exact Input (i.e. Set input amount and swap for target token)
     * @param params SwapParamsExactIn struct
     */
    function swapAssetExactIn(SwapParamsExactIn calldata params) external {
        IERC20(params.tokenFrom).forceApprove(params.uniswapRouter, params.amount);
        ISwapRouter(params.uniswapRouter).exactInput(
            ISwapRouter.ExactInputParams({
                path: params.path,
                recipient: params.recipient,
                deadline: params.deadline,
                amountIn: params.amount,
                amountOutMinimum: params.amountOutMinimum
            })
        );
    }

    /**
     * @notice Swap token on Uniswap with Exact Output (i.e. Set output amount and swap with required amount of input token)
     * @param params SwapParamsExactOut struct
     */
    function swapAssetExactOut(SwapParamsExactOut calldata params) external {
        IERC20(params.tokenFrom).forceApprove(params.uniswapRouter, params.amountInMaximum);
        uint256 amountIn = ISwapRouter(params.uniswapRouter).exactOutput(
            ISwapRouter.ExactOutputParams({
                path: params.path,
                recipient: params.recipient,
                deadline: params.deadline,
                amountOut: params.amount,
                amountInMaximum: params.amountInMaximum
            })
        );

        // Reset approved leftover input token back to 0, if there is any leftover approved amount
        if (amountIn < params.amountInMaximum) {
            IERC20(params.tokenFrom).forceApprove(params.uniswapRouter, 0);
        }
    }
}
