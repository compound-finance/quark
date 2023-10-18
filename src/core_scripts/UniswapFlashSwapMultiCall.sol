// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./lib/PoolAddress.sol";
import "./CoreScript.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract UniswapFlashSwapMultiCall is CoreScript, IUniswapV3SwapCallback {
    using SafeERC20 for IERC20;
    // Constant of uniswap's factory to authorize callback caller for Mainnet, Goerli, Arbitrum, Optimism, Polygon

    address constant UNISWAP_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    error FailedFlashSwap(address token);
    error InvalidCaller();

    /// @notice Input for flash swap multicall when interact with UniswapV3 Pool swap function
    struct FlashSwapMultiCallInput {
        PoolAddress.PoolKey poolKey;
        address[] callContracts;
        bytes[] callDatas;
        uint256[] callValues;
        bool withChecks;
        address[] checkContracts;
        bytes4[] checkSelectors;
        bytes[] checkValues;
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
        bool withChecks;
        address[] checkContracts;
        bytes4[] checkSelectors;
        bytes[] checkValues;
    }

    /**
     * @notice Execute multiple calls in a single transaction with flash swap
     * @param payload Struct of UniswapFlashSwapMultiCallPayload contains pool info and MultiCall inputs
     */
    function run(UniswapFlashSwapMultiCallPayload memory payload) external {
        // Reorder the token0, token1 to ensure it's in the correct order token1 > token0
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
                    callValues: payload.callValues,
                    withChecks: payload.withChecks,
                    checkContracts: payload.checkContracts,
                    checkSelectors: payload.checkSelectors,
                    checkValues: payload.checkValues
                })
            )
        );
    }

    /**
     * @notice Callback function for Uniswap flash swap
     * @param amount0Delta Amount of token0 owed (only need to repay positive value)
     * @param amount1Delta Amount of token1 owed (only need to repay positive value)
     * @param data Data passed from UniswapV3Pool.swap() which contains MultiCall inputs to execute before sending the owed amount back
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        FlashSwapMultiCallInput memory input = abi.decode(data, (FlashSwapMultiCallInput));
        IUniswapV3Pool pool = IUniswapV3Pool(PoolAddress.computeAddress(UNISWAP_FACTORY, input.poolKey));
        if (msg.sender != address(pool)) {
            revert InvalidCaller();
        }

        if (input.withChecks) {
            // Execute multiple calls with checks
            executeMultiChecksInternal(
                input.callContracts,
                input.callDatas,
                input.callValues,
                input.checkContracts,
                input.checkSelectors,
                input.checkValues
            );
        } else {
            // Execute multiple calls without checks
            executeMultiInternal(input.callContracts, input.callDatas, input.callValues);
        }

        // Attempt to pay back amount owed after multi calls completed
        if (amount0Delta > 0) {
            IERC20(input.poolKey.token0).safeTransfer(address(pool), uint256(amount0Delta));
        }

        if (amount1Delta > 0) {
            IERC20(input.poolKey.token1).safeTransfer(address(pool), uint256(amount1Delta));
        }
    }
}
