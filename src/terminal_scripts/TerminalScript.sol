// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.21;

import "v3-periphery/interfaces/ISwapRouter.sol";
import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "./../QuarkScript.sol";
import "./interfaces/IComet.sol";
import "./interfaces/ICometRewards.sol";

// TODO: Will need to add support for E-Comet once E-Comet has been deployed
contract CometSupplyActions {
    using SafeERC20 for IERC20;

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
        IERC20(asset).forceApprove(comet, amount);
        IComet(comet).supplyFrom(from, to, asset, amount);
    }

    /**
     * @notice Supply multiple assets to Comet
     * @param comet The Comet address
     * @param assets The assets to supply
     * @param amounts The amounts of each asset to supply
     */
    function supplyMultipleAssets(address comet, address[] calldata assets, uint256[] calldata amounts) external {
        for (uint256 i = 0; i < assets.length; i++) {
            IERC20(assets[i]).forceApprove(comet, amounts[i]);
            IComet(comet).supply(assets[i], amounts[i]);
        }
    }
}

contract CometWithdrawActions {
    using SafeERC20 for IERC20;

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
        for (uint256 i = 0; i < assets.length; i++) {
            IComet(comet).withdraw(assets[i], amounts[i]);
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
                deadline: block.timestamp,
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
        ISwapRouter(params.uniswapRouter).exactOutput(
            ISwapRouter.ExactOutputParams({
                path: params.path,
                recipient: params.recipient,
                deadline: block.timestamp,
                amountOut: params.amount,
                amountInMaximum: params.amountInMaximum
            })
        );
    }
}

contract TransferActions is QuarkScript {
    using SafeERC20 for IERC20;

    error TransferFailed(bytes data);
    error ReentrantCall();

    /// @notice storage location for the re-entrancy guard
    bytes32 public constant REENTRANCY_FLAG = keccak256("terminal.scripts.reentrancy.guard.v1");

    /**
     * @notice Transfer ERC20 token
     * @param token The token address
     * @param recipient The recipient address
     * @param amount The amount to transfer
     */
    function transferERC20Token(address token, address recipient, uint256 amount) external {
        IERC20(token).safeTransfer(recipient, amount);
    }

    /**
     * @notice Transfer native token (i.e. ETH)
     * @param recipient The recipient address
     * @param amount The amount to transfer
     */
    function transferNativeToken(address recipient, uint256 amount) external {
        if (read(REENTRANCY_FLAG) == bytes32(uint256(1))) {
            revert ReentrantCall();
        }
        write(REENTRANCY_FLAG, bytes32(uint256(1)));
        (bool success, bytes memory data) = payable(recipient).call{value: amount}("");
        if (!success) {
            revert TransferFailed(data);
        }
        write(REENTRANCY_FLAG, bytes32(uint256(0)));
    }
}

contract CometClaimRewards {
    /**
     * @notice Claim rewards
     * @param cometRewards The CometRewards address
     * @param comet The Comet address
     * @param recipient The recipient address, that will receive the COMP rewards
     */
    function claim(address cometRewards, address comet, address recipient) external {
        ICometRewards(cometRewards).claim(comet, recipient, true);
    }
}

contract CometSupplyMultipleAssetsAndBorrow {
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

contract CometRepayAndWithdrawMultipleAssets {
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