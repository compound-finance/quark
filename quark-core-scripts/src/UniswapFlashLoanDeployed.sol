// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "v3-core/contracts/interfaces/callback/IUniswapV3FlashCallback.sol";

import "quark-core/src/QuarkScript.sol";

import "quark-core-scripts/src/vendor/uniswap_v3_periphery/PoolAddress.sol";
import "quark-core-scripts/src/lib/UniswapFactoryAddress.sol";

contract UniswapFlashLoanDeployed is IUniswapV3FlashCallback, QuarkScript {
    constructor() payable {
        assembly {
            // Note: this short-circuits the constructor, which usually returns this contract's
            //       own "deployedCode" as its return value. Thus, the input `code` _becomes_
            //       this stub's deployedCode on chain, allowing you to deploy a contract
            //       with any runtime code.
            //
            // Note: `return`ing from a constructor is not documented in Solidity. This could be
            //       considered to breach on "undocumented" behavior. This functionality does
            //       **not** play well with const immutables.
            // Note: Magic numbers are weird. Here, we pick a number from observing the deployed size
            //       of this contract in the output of the build. A few points: a) we would prefer that
            //       we could do `type(CodeJarStub).creationCode.length` in this code, but that's
            //       expressly forbidden by Solidity. That would be fine, except in Solidity's own
            //       Yul code, they use `datasize("CodeJarStub")` and _that's_ okay for some reason,
            //       b) the idea of knowing where the constructor args start based on knowing the code size,
            //       via `datasize("CodeJarStub")` is perfectly normal and the only way to decode arguments,
            //       so the weird part here is simply the idea of hard-coding it since Solidity doesn't
            //       expose the size of the creation code itself to contracts, c) we tried to use
            //       `const programSz = type(CodeJarStubSize).creationCode.length` as a contract-constant,
            //       however, Solidity doesn't believe that to be a constant and thus creates runtime code
            //       for that. Weirdly `keccak256(type(CodeJarStubSize).creationCode)` is considered to be
            //       a constant, but I disgress, d) we test this value in a variety of ways. If the magic
            //       value truly changes, then the test cases would fail. We both check for it expressly,
            //       but also any test that relies on this working would immediately break otherwise.
            let programSz := 20 // It's magic. It's pure darned magic. Please don't look behind the curtain.
            let argSz := sub(codesize(), programSz)
            codecopy(0, programSz, argSz)
            return(0, argSz)
        }
    }

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
            (payload.token0, payload.token1) = (payload.token1, payload.token0);
            (payload.amount0, payload.amount1) = (payload.amount1, payload.amount0);
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
        if (input.amount0 + fee0 > 0) {
            IERC20(input.poolKey.token0).safeTransfer(address(pool), input.amount0 + fee0);
        }

        if (input.amount1 + fee1 > 0) {
            IERC20(input.poolKey.token1).safeTransfer(address(pool), input.amount1 + fee1);
        }
    }
}