// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "./lib/PoolAddress.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "v3-core/contracts/interfaces/callback/IUniswapV3FlashCallback.sol";

contract UniswapFlashLoanMultiCall is IUniswapV3FlashCallback {
    using SafeERC20 for IERC20;

    // Constant of uniswap's factory to authorize callback caller for Mainnet, Goerli, Arbitrum, Optimism, Polygon
    // TODO: Need to find a way to make this configurable for other chains, but not too freely adjustable in callback
    address constant UNISWAP_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    error FailedFlashRepay(address token);
    error InvalidCaller();
    error InvalidInput();
    error MultiCallError(uint256 callIndex, address callContract, bytes callData, uint256 callValue, bytes err);

    /// @notice Input for flash loan multicall when interacting with UniswapV3 Pool contract
    struct FlashLoanInput {
        uint256 amount0;
        uint256 amount1;
        PoolAddress.PoolKey poolKey;
        address[] callContracts;
        bytes[] callDatas;
        uint256[] callValues;
    }

    /// @notice Payload for UniswapFlashLoanMultiCall
    struct UniswapFlashLoanMultiCallPayload {
        address token0;
        address token1;
        uint24 fee;
        uint256 amount0;
        uint256 amount1;
        address[] callContracts;
        bytes[] callDatas;
        uint256[] callValues;
    }

    /**
     * @notice Execute multiple calls in a single transaction with flash loan
     * @param payload UniswapFlashLoanMultiCallPayload struct; contains pool info and MultiCall inputs
     */
    function run(UniswapFlashLoanMultiCallPayload memory payload) external {
        // Reorder token0, token1 to ensure token1 > token0
        if (payload.token0 > payload.token1) {
            (payload.token0, payload.token1) = (payload.token1, payload.token0);
            (payload.amount0, payload.amount1) = (payload.amount1, payload.amount0);
        }
        IUniswapV3Pool(
            PoolAddress.computeAddress(
                UNISWAP_FACTORY, PoolAddress.getPoolKey(payload.token0, payload.token1, payload.fee)
            )
        ).flash(
            address(this),
            payload.amount0,
            payload.amount1,
            abi.encode(
                FlashLoanInput({
                    amount0: payload.amount0,
                    amount1: payload.amount1,
                    poolKey: PoolAddress.getPoolKey(payload.token0, payload.token1, payload.fee),
                    callContracts: payload.callContracts,
                    callDatas: payload.callDatas,
                    callValues: payload.callValues
                })
            )
        );
    }

    /**
     * @notice Callback function for Uniswap flash loan
     * @param fee0 token0 fee to repay to the flash loan pool
     * @param fee1 token1 fee to repay to the flash loan pool
     * @param data FlashLoanInput encoded to bytes passed from IUniswapV3Pool.flash(); contains a MultiCall to execute (possibly with checks) before repaying the flash loan
     */
    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata data) external {
        FlashLoanInput memory input = abi.decode(data, (FlashLoanInput));
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
        if (input.amount0 + fee0 > 0) {
            IERC20(input.poolKey.token0).safeTransfer(address(pool), input.amount0 + fee0);
        }

        if (input.amount1 + fee1 > 0) {
            IERC20(input.poolKey.token1).safeTransfer(address(pool), input.amount1 + fee1);
        }
    }
}
