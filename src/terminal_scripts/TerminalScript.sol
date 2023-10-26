// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "v3-periphery/interfaces/ISwapRouter.sol";
import "openzeppelin/token/ERC20/IERC20.sol";
import "./interfaces/IComet.sol";
import "./interfaces/ICometRewards.sol";

contract TerminalScript {
    error TransferFailed(bytes data);
    error AccountNotAtRisk();

    function supplyBaseToV3(address comet, uint256 amount) external {
        IERC20(IComet(comet).baseToken()).approve(comet, amount);
        IComet(comet).supply(IComet(comet).baseToken(), amount);
    }

    function withdrawBaseFromV3(address comet, uint256 amount) external {
        IComet(comet).withdraw(IComet(comet).baseToken(), amount);
    }

    function supplyCollateralToV3(address comet, address asset, uint256 amount) external {
        IERC20(asset).approve(comet, amount);
        IComet(comet).supply(asset, amount);
    }

    function withdrawCollateralFromV3(address comet, address asset, uint256 amount) external {
        IComet(comet).withdraw(asset, amount);
    }

    function buyAssetWithUSDCExactIn(
        address uniswapRouter,
        address usdc,
        uint256 amount,
        uint256 amountOutMinimum,
        bytes calldata path
    ) external {
        IERC20(usdc).approve(uniswapRouter, amount);
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

    function buyAssetWithUSDCExactOut(
        address uniswapRouter,
        address usdc,
        uint256 amount,
        uint256 amountInMaximum,
        bytes calldata path
    ) external {
        IERC20(usdc).approve(uniswapRouter, amount);
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

    function sellAssetWithUSDCExactIn(
        address uniswapRouter,
        address asset,
        uint256 amount,
        uint256 amountOutMinimum,
        bytes calldata path
    ) external {
        IERC20(asset).approve(uniswapRouter, amount);
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

    function sellAssetWithUSDCExactOut(
        address uniswapRouter,
        address asset,
        uint256 amount,
        uint256 amountInMaximum,
        bytes calldata path
    ) external {
        IERC20(asset).approve(uniswapRouter, amount);
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

    function sendERC20Token(address token, address recipient, uint256 amount) external {
        IERC20(token).transfer(recipient, amount);
    }

    function sendNativeToken(address recipient, uint256 amount) external {
        (bool success, bytes memory data) = payable(recipient).call{value: amount}("");
        if (!success) {
            revert TransferFailed(data);
        }
    }

    function claimCOMP(address cometRewards, address comet) external {
        ICometRewards(cometRewards).claim(comet, msg.sender, true);
    }

    function supplyMultipleCollateralAssetsToV3(address comet, address[] calldata assets, uint256[] calldata amount)
        external
    {
        for (uint256 i = 0; i < assets.length; i++) {
            IComet(comet).supply(assets[i], amount[i]);
        }
    }

    function withdrawMultipleCollateralAssetsFromV3(address comet, address[] calldata assets, uint256[] calldata amount)
        external
    {
        for (uint256 i = 0; i < assets.length; i++) {
            IComet(comet).withdraw(assets[i], amount[i]);
        }
    }
}
