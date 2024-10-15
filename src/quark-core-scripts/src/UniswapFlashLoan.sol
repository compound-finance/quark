// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "v3-core/contracts/interfaces/callback/IUniswapV3FlashCallback.sol";

import "quark-core/src/QuarkScript.sol";

import "quark-core-scripts/src/vendor/uniswap_v3_periphery/PoolAddress.sol";
import "quark-core-scripts/src/lib/UniswapFactoryAddress.sol";

contract UniswapFlashLoan is IUniswapV3FlashCallback, QuarkScript {
    using SafeERC20 for IERC20;

    error InvalidCaller();

    /// @notice Input for flash loan when interacting with UniswapV3 Pool contract
    struct FlashLoanCallbackPayload {
        uint256 amount0;
        uint256 amount1;
        PoolAddress.PoolKey poolKey;
        address callContract;
        bytes callData;
    }

    /// @notice Payload for UniswapFlashLoan
    struct UniswapFlashLoanPayload {
        address token0;
        address token1;
        uint24 fee;
        uint256 amount0;
        uint256 amount1;
        address callContract;
        bytes callData;
    }

    /**
     * @notice Execute multiple calls in a single transaction after taking out a flash loan
     * @param payload UniswapFlashLoanPayload struct; contains token and fee info and inputs
     */
    function run(UniswapFlashLoanPayload memory payload) external {
        allowCallback();
        PoolAddress.PoolKey memory poolKey = PoolAddress.getPoolKey(payload.token0, payload.token1, payload.fee);
        // Reorder token0, token1 to ensure token1 > token0
        if (payload.token0 > payload.token1) {
            (payload.token0, payload.token1, payload.amount0, payload.amount1) =
                (payload.token1, payload.token0, payload.amount1, payload.amount0);
        }
        IUniswapV3Pool(PoolAddress.computeAddress(UniswapFactoryAddress.getAddress(), poolKey)).flash(
            address(this),
            payload.amount0,
            payload.amount1,
            abi.encode(
                FlashLoanCallbackPayload({
                    amount0: payload.amount0,
                    amount1: payload.amount1,
                    poolKey: poolKey,
                    callContract: payload.callContract,
                    callData: payload.callData
                })
            )
        );
    }

    /**
     * @notice Callback function for Uniswap flash loan
     * @param fee0 amount of token0 fee to repay to the flash loan pool
     * @param fee1 amount of token1 fee to repay to the flash loan pool
     * @param data FlashLoanCallbackPayload encoded to bytes passed from IUniswapV3Pool.flash(); contains scripts info to execute before repaying the flash loan
     */
    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata data) external {
        disallowCallback();
        FlashLoanCallbackPayload memory input = abi.decode(data, (FlashLoanCallbackPayload));
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
        uint256 repayAmount = input.amount0 + fee0;
        if (repayAmount > 0) {
            IERC20(input.poolKey.token0).safeTransfer(address(pool), repayAmount);
        }

        repayAmount = input.amount1 + fee1;
        if (repayAmount > 0) {
            IERC20(input.poolKey.token1).safeTransfer(address(pool), repayAmount);
        }
    }
}
