// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "v3-periphery/interfaces/ISwapRouter.sol";
import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IComet.sol";
import "./interfaces/ICometRewards.sol";

contract TerminalScript {
    // To handle non-standard ERC20 tokens (i.e. USDT)
    using SafeERC20 for IERC20;

    error TransferFailed(bytes data);

    function supplyToComet(address comet, address asset, uint256 amount) external {
        IERC20(asset).safeIncreaseAllowance(comet, amount);
        IComet(comet).supply(asset, amount);
    }

    function withdrawFromComet(address comet, address asset, uint256 amount) external {
        IComet(comet).withdraw(asset, amount);
    }

    function swapAssetExactIn(
        address uniswapRouter,
        address assetFrom,
        uint256 amount,
        uint256 amountOutMinimum,
        bytes calldata path
    ) external {
        IERC20(assetFrom).safeIncreaseAllowance(uniswapRouter, amount);
        ISwapRouter(uniswapRouter).exactInput(
            ISwapRouter.ExactInputParams({
                path: path,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amount,
                amountOutMinimum: amountOutMinimum
            })
        );
    }

    function swapAssetExactOut(
        address uniswapRouter,
        address assetFrom,
        uint256 amount,
        uint256 amountInMaximum,
        bytes calldata path
    ) external {
        IERC20(assetFrom).safeIncreaseAllowance(uniswapRouter, amountInMaximum);
        ISwapRouter(uniswapRouter).exactOutput(
            ISwapRouter.ExactOutputParams({
                path: path,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountOut: amount,
                amountInMaximum: amountInMaximum
            })
        );
    }

    function transferERC20Token(address token, address recipient, uint256 amount) external {
        IERC20(token).safeTransfer(recipient, amount);
    }

    function transferNativeToken(address recipient, uint256 amount) external {
        (bool success, bytes memory data) = payable(recipient).call{value: amount}("");
        if (!success) {
            revert TransferFailed(data);
        }
    }

    function claimCOMP(address cometRewards, address comet) external {
        ICometRewards(cometRewards).claim(comet, msg.sender, true);
    }

    function supplyMultipleAssetsToComet(address comet, address[] calldata assets, uint256[] calldata amounts)
        external
    {
        for (uint256 i = 0; i < assets.length; i++) {
            IERC20(assets[i]).safeIncreaseAllowance(comet, amounts[i]);
            IComet(comet).supply(assets[i], amounts[i]);
        }
    }

    function withdrawMultipleAssetsFromComet(address comet, address[] calldata assets, uint256[] calldata amounts)
        external
    {
        for (uint256 i = 0; i < assets.length; i++) {
            IComet(comet).withdraw(assets[i], amounts[i]);
        }
    }
}
