// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../QuarkScript.sol";

interface IFlashMulticalErc20 {
  function transfer(address to, uint256 amount) external returns (bool);
}

interface FlashMulticallUniswapPool {
    /// @notice Receive token0 and/or token1 and pay it back, plus a fee, in the callback
    /// @dev The caller of this method receives a callback in the form of IUniswapV3FlashCallback#uniswapV3FlashCallback
    /// @dev Can be used to donate underlying tokens pro-rata to currently in-range liquidity providers by calling
    /// with 0 amount{0,1} and sending the donation amount(s) from the callback
    /// @param recipient The address which will receive the token0 and token1 amounts
    /// @param amount0 The amount of token0 to send
    /// @param amount1 The amount of token1 to send
    /// @param data Any data to be passed through to the callback
    function flash(
        address recipient,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;

    /// @notice The first of the two tokens of the pool, sorted by address
    /// @return The token contract address
    function token0() external view returns (address);

    /// @notice The second of the two tokens of the pool, sorted by address
    /// @return The token contract address
    function token1() external view returns (address);
}

contract FlashMulticall is QuarkScript {
    error InvalidInput();
    error CallError(uint256 n, address callContract, bytes callData, uint256 callValue, bytes err);
    error InvalidCaller();
    error FailedFlashRepay(address token);

    address private flashPool;

    struct FlashMulticallInput {
        address pool;
        uint256 amount0;
        uint256 amount1;
        address[] callContracts;
        bytes[] callDatas;
        uint256[] callValues;
    }

    function run(address pool, uint256 amount0, uint256 amount1, address[] calldata callContracts, bytes[] calldata callDatas, uint256[] calldata callValues) external onlyRelayer returns (bytes memory) {
        // We could probably improve this, but we store the flash pool in storage so we can 
        // later check it's the correct caller for the flash callback. Otherwise we'll
        // need to track the router or something to check tha the caller for the callback
        // is legit.
        require(flashPool == address(0));
        flashPool = pool;
        bytes memory data = abi.encode(FlashMulticallInput({
            pool: pool,
            amount0: amount0,
            amount1: amount1,
            callContracts: callContracts,
            callDatas: callDatas,
            callValues: callValues
        }));

        FlashMulticallUniswapPool(pool).flash(
            address(this),
            amount0,
            amount1,
            data
        );

        return abi.encode(hex"");
    }

    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata data) external {
        if (msg.sender != flashPool) {
            revert InvalidCaller();
        }

        FlashMulticallInput memory input = abi.decode(data, (FlashMulticallInput));

        FlashMulticallUniswapPool pool = FlashMulticallUniswapPool(input.pool);
        if (input.callContracts.length != input.callDatas.length) {
            revert InvalidInput();
        }

        for (uint256 i = 0; i < input.callContracts.length; i++) {
            address callContract = input.callContracts[i];
            if (callContract == 0x906f4bD1940737091f18247eAa870D928A85b9Ce) { // keccak("tx.origin")[0:20]
                callContract = tx.origin;
            }
            bytes memory callData = input.callDatas[i];
            uint256 callValue = input.callValues[i];
            (bool success, bytes memory returnData) = callContract.call{value: callValue}(callData);
            if (!success) {
                revert CallError(i, callContract, callData, callValue, returnData);
            }
        }

        // Note: we require that we have enough tokens (from the calls) to repay the
        //       flash loan with the fee. If not, these calls below will fail.

        uint256 amountPlusFee0 = input.amount0 + fee0;
        if (amountPlusFee0 > 0) {
            address token0 = pool.token0();

            if (!IFlashMulticalErc20(token0).transfer(address(pool), amountPlusFee0)) {
                revert FailedFlashRepay(token0);
            }
        }

        uint256 amountPlusFee1 = input.amount1 + fee1;
        if (amountPlusFee1 > 0) {
            address token1 = pool.token1();

            if (!IFlashMulticalErc20(token1).transfer(address(pool), amountPlusFee1)) {
                revert FailedFlashRepay(token1);
            }
        }

        flashPool = address(0);
    }

    // Allow unwrapping Ether
    receive() external payable {}
}
