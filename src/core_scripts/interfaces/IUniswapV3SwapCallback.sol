// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
interface IUniswapV3SwapCallback {
  function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}