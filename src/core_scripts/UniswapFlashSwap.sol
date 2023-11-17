// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "./../vendor/uniswap_v3_periphery/PoolAddress.sol";
import "./lib/UniswapFactoryAddress.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "../QuarkScript.sol";

contract UniswapFlashSwap is IUniswapV3SwapCallback, QuarkScript {
    using SafeERC20 for IERC20;

    error InvalidCaller();

    /// @notice Input for flash swap multicall when interacting with UniswapV3 Pool swap function
    struct FlashSwapMulticallInput {
        PoolAddress.PoolKey poolKey;
        address callContract;
        bytes callData;
    }

    /// @notice Payload for UniswapFlashSwap
    struct UniswapFlashSwapMulticallPayload {
        address token0;
        address token1;
        uint24 fee;
        uint256 amount0;
        uint256 amount1;
        uint160 sqrtPriceLimitX96;
        address callContract;
        bytes callData;
    }

    /**
     * @notice Execute multiple calls in a single transaction with flash swap
     * @param payload Struct containing pool info and Multicall to execute before repaying the flash swap
     */
    function run(UniswapFlashSwapMulticallPayload memory payload) external {
        allowCallback();
        // Reorder token0, token1 to ensure token1 > token0
        if (payload.token0 > payload.token1) {
            (payload.token0, payload.token1) = (payload.token1, payload.token0);
            (payload.amount0, payload.amount1) = (payload.amount1, payload.amount0);
        }

        IUniswapV3Pool(
            PoolAddress.computeAddress(
                UniswapFactoryAddress.getAddress(), PoolAddress.getPoolKey(payload.token0, payload.token1, payload.fee)
            )
        ).swap(
            address(this),
            payload.amount1 > payload.amount0 ? true : false,
            payload.amount1 > payload.amount0 ? -int256(payload.amount1) : -int256(payload.amount0),
            payload.sqrtPriceLimitX96,
            abi.encode(
                FlashSwapMulticallInput({
                    poolKey: PoolAddress.getPoolKey(payload.token0, payload.token1, payload.fee),
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
     * @param data FlashSwapMulticall encoded to bytes passed from UniswapV3Pool.swap(); contains a Multicall to execute (possibly with checks) before returning the owed amount
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        FlashSwapMulticallInput memory input = abi.decode(data, (FlashSwapMulticallInput));
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

        // Attempt to pay back amount owed after executing Multicall
        if (amount0Delta > 0) {
            IERC20(input.poolKey.token0).safeTransfer(address(pool), uint256(amount0Delta));
        }

        if (amount1Delta > 0) {
            IERC20(input.poolKey.token1).safeTransfer(address(pool), uint256(amount1Delta));
        }
    }
}
