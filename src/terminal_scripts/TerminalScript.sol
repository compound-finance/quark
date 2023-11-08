// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "v3-periphery/interfaces/ISwapRouter.sol";
import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IComet.sol";
import "./interfaces/ICometRewards.sol";

// TODO: Will need to add support for E-Comet once E-Comet has been deployed
contract CometSupplyActions {
    using SafeERC20 for IERC20;
    /**
     *   @dev Supply an asset to Comet
     *   @param comet The Comet address
     *   @param asset The asset address
     *   @param amount The amount to supply
     */

    function supply(address comet, address asset, uint256 amount) external {
        IERC20(asset).forceApprove(comet, amount);
        IComet(comet).supply(asset, amount);
    }

    /**
     * @dev Supply an asset to Comet to a specific address
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
     *   @dev Supply an asset to Comet from one address to another address
     *   @param comet The Comet address
     *   @param from The from address
     *   @param to The to address
     *   @param asset The asset address
     *   @param amount The amount to supply
     */
    function supplyFrom(address comet, address from, address to, address asset, uint256 amount) external {
        IERC20(asset).forceApprove(comet, amount);
        IComet(comet).supplyFrom(from, to, asset, amount);
    }
}

contract CometWithdrawActions {
    using SafeERC20 for IERC20;
    /**
     *  @dev Withdraw an asset from Comet
     *  @param comet The Comet address
     *  @param asset The asset address
     *  @param amount The amount to withdraw
     */

    function withdraw(address comet, address asset, uint256 amount) external {
        IComet(comet).withdraw(asset, amount);
    }

    /**
     * @dev Withdraw an asset from Comet to a specific address
     * @param comet The Comet address
     * @param to The recipient address
     * @param asset The asset address
     * @param amount The amount to withdraw
     */
    function withdrawTo(address comet, address to, address asset, uint256 amount) external {
        IComet(comet).withdrawTo(to, asset, amount);
    }

    /**
     *   @dev Withdraw an asset from Comet from one address to another address
     *   @param comet The Comet address
     *   @param from The from address
     *   @param to The to address
     *   @param asset The asset address
     *   @param amount The amount to withdraw
     */
    function withdrawFrom(address comet, address from, address to, address asset, uint256 amount) external {
        IComet(comet).withdrawFrom(from, to, asset, amount);
    }
}

contract SwapActions {
    using SafeERC20 for IERC20;
    /**
     * @dev Swap token on Uniswap with Exact Input (i.e. Set input amount and swap for target token)
     * @param uniswapRouter The Uniswap router address
     * @param recipient The recipient address that will receive the swapped token
     * @param tokenFrom The token to swap from
     * @param amount The token amount to swap
     * @param amountOutMinimum The minimum amount of target token to receive (revert if return amount is less than this)
     */

    function swapAssetExactIn(
        address uniswapRouter,
        address recipient,
        address tokenFrom,
        uint256 amount,
        uint256 amountOutMinimum,
        bytes calldata path
    ) external {
        IERC20(tokenFrom).forceApprove(uniswapRouter, amount);
        ISwapRouter(uniswapRouter).exactInput(
            ISwapRouter.ExactInputParams({
                path: path,
                recipient: recipient,
                deadline: block.timestamp,
                amountIn: amount,
                amountOutMinimum: amountOutMinimum
            })
        );
    }

    /**
     * @dev Swap token on Uniswap with Exact Output (i.e. Set output amount and swap with required amount token)
     * @param uniswapRouter The Uniswap router address
     * @param recipient The recipient address that will receive the swapped token
     * @param tokenFrom The token to swap from
     * @param amount The target token amount to receive
     * @param amountInMaximum The maximum amount of input token to spend (revert if input amount is greater than this)
     */
    function swapAssetExactOut(
        address uniswapRouter,
        address recipient,
        address tokenFrom,
        uint256 amount,
        uint256 amountInMaximum,
        bytes calldata path
    ) external {
        IERC20(tokenFrom).forceApprove(uniswapRouter, amountInMaximum);
        ISwapRouter(uniswapRouter).exactOutput(
            ISwapRouter.ExactOutputParams({
                path: path,
                recipient: recipient,
                deadline: block.timestamp,
                amountOut: amount,
                amountInMaximum: amountInMaximum
            })
        );
    }
}

contract TransferActions {
    using SafeERC20 for IERC20;

    error TransferFailed(bytes data);

    /**
     * @dev Transfer ERC20 token
     * @param token The token address
     * @param recipient The recipient address
     * @param amount The amount to transfer
     */
    function transferERC20Token(address token, address recipient, uint256 amount) external {
        IERC20(token).safeTransfer(recipient, amount);
    }

    /**
     * @dev Transfer native token (i.e. ETH)
     * @param recipient The recipient address
     * @param amount The amount to transfer
     */
    function transferNativeToken(address recipient, uint256 amount) external {
        (bool success, bytes memory data) = payable(recipient).call{value: amount}("");
        if (!success) {
            revert TransferFailed(data);
        }
    }
}

contract ClaimRewards {
    /**
     * @dev Claim rewards
     * @param cometRewards The CometRewards address
     * @param comet The Comet address
     * @param recipient The recipient address, that will receive the COMP rewards
     */
    function claim(address cometRewards, address comet, address recipient) external {
        ICometRewards(cometRewards).claim(comet, recipient, true);
    }
}

contract SupplyMultipleAssetsToComet {
    // To handle non-standard ERC20 tokens (i.e. USDT)
    using SafeERC20 for IERC20;

    /**
     * @dev Supply multiple assets to Comet
     * @param comet The Comet address
     * @param assets The assets to supply
     * @param amounts The amounts of each asset to supply
     */
    function run(address comet, address[] calldata assets, uint256[] calldata amounts) external {
        for (uint256 i = 0; i < assets.length; i++) {
            IERC20(assets[i]).forceApprove(comet, amounts[i]);
            IComet(comet).supply(assets[i], amounts[i]);
        }
    }
}

contract WithdrawMultipleAssetsFromComet {
    // To handle non-standard ERC20 tokens (i.e. USDT)
    using SafeERC20 for IERC20;

    /**
     * @dev Withdraw multiple assets from Comet
     * @param comet The Comet address
     * @param assets The assets to withdraw
     * @param amounts The amounts of each asset to withdraw
     */
    function run(address comet, address[] calldata assets, uint256[] calldata amounts) external {
        for (uint256 i = 0; i < assets.length; i++) {
            IComet(comet).withdraw(assets[i], amounts[i]);
        }
    }
}

contract SupplyMultipleAssetsAndBorrowOnComet {
    // To handle non-standard ERC20 tokens (i.e. USDT)
    using SafeERC20 for IERC20;

    function run(address comet, address[] calldata assets, uint256[] calldata amounts, address usdc, uint256 borrow)
        external
    {
        for (uint256 i = 0; i < assets.length; i++) {
            IERC20(assets[i]).forceApprove(comet, amounts[i]);
            IComet(comet).supply(assets[i], amounts[i]);
        }
        IComet(comet).withdraw(usdc, borrow);
    }
}

contract RepayAndWithdrawMultipleAssetsOnComet {
    // To handle non-standard ERC20 tokens (i.e. USDT)
    using SafeERC20 for IERC20;

    function run(address comet, address[] calldata assets, uint256[] calldata amounts, address usdc, uint256 repay)
        external
    {
        IERC20(usdc).forceApprove(comet, repay);
        IComet(comet).supply(usdc, repay);
        for (uint256 i = 0; i < assets.length; i++) {
            IComet(comet).withdraw(assets[i], amounts[i]);
        }
    }
}
