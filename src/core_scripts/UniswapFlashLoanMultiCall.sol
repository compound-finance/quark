// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./interfaces/IERC20NonStandard.sol";
import "./lib/PoolAddress.sol";
import "./CoreScript.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "v3-core/contracts/interfaces/callback/IUniswapV3FlashCallback.sol";

contract UniswapFlashLoanMultiCall is CoreScript, IUniswapV3FlashCallback {
    // Constant of uniswap's factory to authorize callback caller for Mainnet, Goerli, Arbitrum, Optimism, Polygon
    // TODO: Need to find a way to make this configurable for other chains, but not too freely adjustable in callback
    address constant UNISWAP_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    error FailedFlashRepay(address token);
    error InvalidCaller();

    /// @notice Input for flash loan multicall when interact with UniswapV3 Pool contract
    struct FlashLoanInput {
        uint256 amount0;
        uint256 amount1;
        PoolAddress.PoolKey poolKey;
        address[] callContracts;
        bytes[] callCodes;
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
        bytes[] callCodes;
        bytes[] callDatas;
        uint256[] callValues;
    }

    /**
     * @notice Execute multiple calls in a single transaction with flash loan
     * @param payload Struct of UniswapFlashLoanMultiCallPayload contains pool info and MultiCall inputs
     */
    function run(UniswapFlashLoanMultiCallPayload memory payload) external {
        // Reorder the token0, token1 to ensure it's in the correct order token1 > token0
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
                    callCodes: payload.callCodes,
                    callDatas: payload.callDatas,
                    callValues: payload.callValues
                })
            )
        );
    }

    /**
     * @notice Callback function for Uniswap flashloan
     * @param fee0 Fees that need to repay for token0 from the flashloan pool
     * @param fee1 Fees that need to repay for token1 from the flashloan pool
     * @param data Data that passed from invoking IUniswapV3Pool.flash(), which contains MultiCall inputs to execute before repaying the flashloan
     */
    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata data) external {
        FlashLoanInput memory input = abi.decode(data, (FlashLoanInput));
        IUniswapV3Pool pool = IUniswapV3Pool(PoolAddress.computeAddress(UNISWAP_FACTORY, input.poolKey));
        if (msg.sender != address(pool)) {
            revert InvalidCaller();
        }

        executeMultiInternal(input.callContracts, input.callCodes, input.callDatas, input.callValues);

        // Attempt to pay back amount owed after multi calls completed
        if (input.amount0 + fee0 > 0) {
            IERC20NonStandard(input.poolKey.token0).transfer(address(pool), input.amount0 + fee0);
            bool success;
            assembly {
                switch returndatasize()
                case 0 {
                    // This is a non-standard ERC-20
                    success := not(0) // set success to true
                }
                case 32 {
                    // This is a compliant ERC-20
                    returndatacopy(0, 0, 32)
                    success := mload(0) // Set `success = returndata` of override external call
                }
                default {
                    // This is an excessively non-compliant ERC-20, revert.
                    revert(0, 0)
                }
            }
            if (!success) {
                revert FailedFlashRepay(input.poolKey.token0);
            }
        }

        if (input.amount1 + fee1 > 0) {
            IERC20NonStandard(input.poolKey.token1).transfer(address(pool), input.amount1 + fee1);
            bool success;
            assembly {
                switch returndatasize()
                case 0 {
                    // This is a non-standard ERC-20
                    success := not(0) // set success to true
                }
                case 32 {
                    // This is a compliant ERC-20
                    returndatacopy(0, 0, 32)
                    success := mload(0) // Set `success = returndata` of override external call
                }
                default {
                    // This is an excessively non-compliant ERC-20, revert.
                    revert(0, 0)
                }
            }
            if (!success) {
                revert FailedFlashRepay(input.poolKey.token1);
            }
        }
    }
}
