// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "./lib/PoolAddress.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "v3-core/contracts/interfaces/callback/IUniswapV3FlashCallback.sol";
import "../QuarkScript.sol";

contract UniswapFlashLoanMulticall is IUniswapV3FlashCallback, QuarkScript {
    using SafeERC20 for IERC20;

    // Constant of uniswap's factory to authorize callback caller for Mainnet, Goerli, Arbitrum, Optimism, Polygon
    // TODO: Need to find a way to make this configurable for other chains, but not too freely adjustable in callback
    address constant UNISWAP_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    error FailedFlashRepay(address token);
    error InvalidCaller();
    error InvalidInput();
    error MulticallError(uint256 callIndex, address callContract, bytes err);

    /// @notice Input for flash loan multicall when interacting with UniswapV3 Pool contract
    struct FlashLoanCallbackPayload {
        uint256 amount0;
        uint256 amount1;
        PoolAddress.PoolKey poolKey;
        address callContract;
        bytes callData;
    }

    /// @notice Payload for UniswapFlashLoanMulticall
    struct UniswapFlashLoanMulticallPayload {
        address token0;
        address token1;
        uint24 fee;
        uint256 amount0;
        uint256 amount1;
        address callContract;
        bytes callData;
    }

    /**
     * @notice Execute multiple calls in a single transaction with flash loan
     * @param payload UniswapFlashLoanMulticallPayload struct; contains token and fee info and MultiCall inputs
     */
    function run(UniswapFlashLoanMulticallPayload memory payload) external {
        allowCallback();
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
                FlashLoanCallbackPayload({
                    amount0: payload.amount0,
                    amount1: payload.amount1,
                    poolKey: PoolAddress.getPoolKey(payload.token0, payload.token1, payload.fee),
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
     * @param data FlashLoanCallbackPayload encoded to bytes passed from IUniswapV3Pool.flash(); contains a MultiCall to execute before repaying the flash loan
     */
    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata data) external {
        FlashLoanCallbackPayload memory input = abi.decode(data, (FlashLoanCallbackPayload));
        IUniswapV3Pool pool = IUniswapV3Pool(PoolAddress.computeAddress(UNISWAP_FACTORY, input.poolKey));
        if (msg.sender != address(pool)) {
            revert InvalidCaller();
        }

        (bool success, bytes memory returnData) = input.callContract.delegatecall(input.callData);
        if (!success) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
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
