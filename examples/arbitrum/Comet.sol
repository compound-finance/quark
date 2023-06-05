// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IErc20 {
  function approve(address spender, uint256 amount) external returns (bool);
  function balanceOf(address holder) external returns (uint256);
}

interface IComet {
  function supply(address asset, uint amount) external;
  function withdraw(address asset, uint amount) external;
}

interface ISwapRouter {
  struct ExactInputSingleParams {
      address tokenIn;
      address tokenOut;
      uint24 fee;
      address recipient;
      uint256 deadline;
      uint256 amountIn;
      uint256 amountOutMinimum;
      uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

contract Comet {
  IErc20 constant weth = IErc20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
  IErc20 constant arb = IErc20(0x912CE59144191C1204E64559FE8253a0e49E6548);
  IErc20 constant usdc = IErc20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
  IComet constant comet = IComet(0xA5EDBDD9646f8dFF606d7448e414884C7d905dCA);
  ISwapRouter constant swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

  function tradeAndSupply() external {
    uint256 amountIn = 0.2e18;

    weth.approve(address(swapRouter), amountIn);
    ISwapRouter.ExactInputSingleParams memory params =
      ISwapRouter.ExactInputSingleParams({
        tokenIn: address(weth),
        tokenOut: address(arb),
        fee: 3000,
        recipient: address(this),
        deadline: type(uint256).max,
        amountIn: amountIn,
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
    });

    // The call to `exactInputSingle` executes the swap.
    uint256 amountOut = swapRouter.exactInputSingle(params);

    uint256 arbBalance = arb.balanceOf(address(this));

    arb.approve(address(comet), arbBalance);
    comet.supply(address(arb), arbBalance);

    comet.withdraw(address(usdc), 101e6);
  }
}
