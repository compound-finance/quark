// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "./lib/PoolAddress.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract UniswapFlashSwapMultiCall is IUniswapV3SwapCallback {
    using SafeERC20 for IERC20;

    // Constant of uniswap's factory to authorize callback caller for Mainnet, Goerli, Arbitrum, Optimism, Polygon
    address constant UNISWAP_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    error FailedFlashSwap(address token);
    error InvalidCaller();
    error InvalidInput();
    error MultiCallError(uint256 callIndex, address callContract, bytes callData, uint256 callValue, bytes err);

    /// @notice Input for flash swap multicall when interacting with UniswapV3 Pool swap function
    struct FlashSwapMultiCallInput {
        PoolAddress.PoolKey poolKey;
        address[] callContracts;
        bytes[] callDatas;
        uint256[] callValues;
    }

    /// @notice Payload for UniswapFlashSwapMultiCall
    struct UniswapFlashSwapMultiCallPayload {
        address token0;
        address token1;
        uint24 fee;
        uint256 amount0;
        uint256 amount1;
        uint160 sqrtPriceLimitX96;
        address[] callContracts;
        bytes[] callDatas;
        uint256[] callValues;
    }

    /**
     * @notice Execute multiple calls in a single transaction with flash swap
     * @param payload Struct containing pool info and MultiCall to execute before repaying the flash swap
     */
    function run(UniswapFlashSwapMultiCallPayload memory payload) external {
        // Reorder token0, token1 to ensure token1 > token0
        if (payload.token0 > payload.token1) {
            (payload.token0, payload.token1) = (payload.token1, payload.token0);
            (payload.amount0, payload.amount1) = (payload.amount1, payload.amount0);
        }

        IUniswapV3Pool(
            PoolAddress.computeAddress(
                UNISWAP_FACTORY, PoolAddress.getPoolKey(payload.token0, payload.token1, payload.fee)
            )
        ).swap(
            address(this),
            payload.amount1 > payload.amount0 ? true : false,
            payload.amount1 > payload.amount0 ? -int256(payload.amount1) : -int256(payload.amount0),
            payload.sqrtPriceLimitX96,
            abi.encode(
                FlashSwapMultiCallInput({
                    poolKey: PoolAddress.getPoolKey(payload.token0, payload.token1, payload.fee),
                    callContracts: payload.callContracts,
                    callDatas: payload.callDatas,
                    callValues: payload.callValues
                })
            )
        );
    }

    /**
     * @notice Callback function for Uniswap flash swap
     * @param amount0Delta Amount of token0 owed (only need to repay positive value)
     * @param amount1Delta Amount of token1 owed (only need to repay positive value)
     * @param data FlashSwapMultiCall encoded to bytes passed from UniswapV3Pool.swap(); contains a MultiCall to execute (possibly with checks) before returning the owed amount
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        FlashSwapMultiCallInput memory input = abi.decode(data, (FlashSwapMultiCallInput));
        IUniswapV3Pool pool = IUniswapV3Pool(PoolAddress.computeAddress(UNISWAP_FACTORY, input.poolKey));
        if (msg.sender != address(pool)) {
            revert InvalidCaller();
        }

        if (
            input.callContracts.length != input.callDatas.length
                || input.callContracts.length != input.callValues.length
        ) {
            revert InvalidInput();
        }

        for (uint256 i = 0; i < input.callContracts.length; i++) {
            (bool success, bytes memory returnData) =
                input.callContracts[i].call{value: input.callValues[i]}(input.callDatas[i]);
            if (!success) {
                revert MultiCallError(i, input.callContracts[i], input.callDatas[i], input.callValues[i], returnData);
            }
        }

        // Attempt to pay back amount owed after executing MultiCall
        if (amount0Delta > 0) {
            IERC20(input.poolKey.token0).safeTransfer(address(pool), uint256(amount0Delta));
        }

        if (amount1Delta > 0) {
            IERC20(input.poolKey.token1).safeTransfer(address(pool), uint256(amount1Delta));
        }
    }
}
