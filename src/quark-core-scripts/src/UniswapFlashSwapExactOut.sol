// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "v3-core/contracts/libraries/SafeCast.sol";

import "quark-core/src/QuarkScript.sol";

import "quark-core-scripts/src/vendor/uniswap_v3_periphery/PoolAddress.sol";
import "quark-core-scripts/src/lib/UniswapFactoryAddress.sol";

contract UniswapFlashSwapExactOut is IUniswapV3SwapCallback, QuarkScript {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    /// Reference: https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/TickMath.sol
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    /// Reference: https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/TickMath.sol
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    error InvalidCaller();

    /// @notice Input for flash swap when interacting with UniswapV3 Pool swap function
    struct FlashSwapExactOutInput {
        PoolAddress.PoolKey poolKey;
        address callContract;
        bytes callData;
    }

    /// @notice Payload for UniswapFlashSwap
    struct UniswapFlashSwapExactOutPayload {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        uint256 amountOut;
        uint160 sqrtPriceLimitX96;
        address callContract;
        bytes callData;
    }

    /**
     * @notice Execute a flash swap with a callback
     * @param payload Struct containing pool info and script info to execute before repaying the flash swap
     */
    function run(UniswapFlashSwapExactOutPayload memory payload) external {
        allowCallback();
        bool zeroForOne = payload.tokenIn < payload.tokenOut;
        PoolAddress.PoolKey memory poolKey = PoolAddress.getPoolKey(payload.tokenIn, payload.tokenOut, payload.fee);
        IUniswapV3Pool(PoolAddress.computeAddress(UniswapFactoryAddress.getAddress(), poolKey)).swap(
            address(this),
            zeroForOne,
            -payload.amountOut.toInt256(),
            payload.sqrtPriceLimitX96 == 0
                ? (zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1)
                : payload.sqrtPriceLimitX96,
            abi.encode(
                FlashSwapExactOutInput({
                    poolKey: poolKey,
                    callContract: payload.callContract,
                    callData: payload.callData
                })
            )
        );
    }

    /**
     * @notice Callback function for Uniswap flash swap
     * @param amount0Delta Amount of token0 owed (only need to repay positive value)
     * @param amount1Delta Amount of token1 owed (only need to repay positive value)
     * @param data FlashSwap encoded to bytes passed from UniswapV3Pool.swap(); contains script info to execute (possibly with checks) before returning the owed amount
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        FlashSwapExactOutInput memory input = abi.decode(data, (FlashSwapExactOutInput));
        IUniswapV3Pool pool =
            IUniswapV3Pool(PoolAddress.computeAddress(UniswapFactoryAddress.getAddress(), input.poolKey));
        if (msg.sender != address(pool)) {
            revert InvalidCaller();
        }

        (bool success, bytes memory returnData) = input.callContract.delegatecall(input.callData);
        if (!success) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }

        // Attempt to pay back amount owed after execution
        if (amount0Delta > 0) {
            IERC20(input.poolKey.token0).safeTransfer(address(pool), uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            IERC20(input.poolKey.token1).safeTransfer(address(pool), uint256(amount1Delta));
        }
    }
}
