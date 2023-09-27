// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../QuarkScript.sol";
import "../interfaces/IERC20NonStandard.sol";
import "../interfaces/IUniswapV2Router.sol";
import "../interfaces/CometInterface.sol";
import "../interfaces/ISwapRouter.sol";

contract CompoundLeverLoop is QuarkScript {
  error InvalidInput();
  error CallError(uint256 n, address callContract, bytes callData, uint256 callValue, bytes err);

  // function run(address[] calldata callContracts, bytes[] calldata callDatas, uint256[] calldata callValues) external onlyRelayer returns (bytes memory) {
  //   if (callContracts.length != callDatas.length) {
  //     revert InvalidInput();
  //   }

  //   for (uint256 i = 0; i < callContracts.length; i++) {
  //     address callContract = callContracts[i];
  //     if (callContract == 0x906f4bD1940737091f18247eAa870D928A85b9Ce) { // keccak("tx.origin")[0:20]
  //       callContract = tx.origin;
  //     }
  //     bytes memory callData = callDatas[i];
  //     uint256 callValue = callValues[i];
  //     (bool success, bytes memory returnData) = callContract.call{value: callValue}(callData);
  //     if (!success) {
  //       revert CallError(i, callContract, callData, callValue, returnData);
  //     }
  //   }
  //   return abi.encode(hex"");
  // }

  function lever(address cometAddress, uint256 targetLeverageRatio, address targetAsset, uint256 baseInputAmount) external onlyRelayer {
    // Supply baseInputAmount to compound (reduce debt)
    CometInterface(cometAddress).supply(targetAsset, baseInputAmount);
    //Load the initial capital of the user in base asset
    // In base asset
    uint256 currentTargetAssetExposureAmount = 
      CometInterface(cometAddress).collateralBalanceOf(address(this), targetAsset) * CometInterface(cometAddress).getPrice(targetAsset) 
      / CometInterface(cometAddress).getAssetInfoByAddress(targetAsset).scale;
    uint256 currentBorrowedBalance = CometInterface(cometAddress).borrowBalanceOf(address(this));
    //leverageRatio = 0 - 500  in %
    uint256 currentLeverageRatio = currentTargetAssetExposureAmount / (currentTargetAssetExposureAmount - currentBorrowedBalance);
    uint256 newAssetHolding = currentTargetAssetExposureAmount * (targetLeverageRatio / currentLeverageRatio);
    uint loopMax = 10;
    if (newAssetHolding > currentTargetAssetExposureAmount){
      // increase leverage
      // 1. Borrow delta from Compound (max is X in one iteration)
      uint256 delta = newAssetHolding - currentTargetAssetExposureAmount;
      while(delta > 0 && loopMax > 0){
        uint256 maxQuota = currentTargetAssetExposureAmount * 
          CometInterface(cometAddress).getAssetInfoByAddress(targetAsset).borrowCollateralFactor / 1e18 - currentBorrowedBalance;
        uint256 left = delta > maxQuota ? maxQuota : delta;
        CometInterface(cometAddress).withdraw(targetAsset, left);
        // Uniswap trade
        uint swapOut = swapViaUniswap(cometAddress, CometInterface(cometAddress).baseToken(), targetAsset, left, 0);
        // Supply back to Compound
        CometInterface(cometAddress).supply(targetAsset, swapOut);
        delta -= left;
        loopMax -= 1;
      }
    } else {
      // decrease leverage
      // 1. Repay delta to Compound by withdrawing collateral and exchange to base
      uint256 delta = currentTargetAssetExposureAmount - newAssetHolding;
      revert("Not implemented");
      // while (delta > 0){
      //   uint256 maxQuota = currentBorrowedBalance;
      //   uint256 left = delta > maxQuota ? maxQuota : delta;
      //   CometInterface(cometAddress).withdraw(targetAsset, left);
      //   // Uniswap trade
      //   // uint swapOut = swapViaUniswap(cometAddress, left, targetAsset, left, 0);
      //   // Supply back to Compound
      //   // CometInterface(cometAddress).supply(targetAsset, swapOut);
      //   delta -= left;
      //   loopMax -= 1;
      // }
    }

  }

  /**
    * @dev Swaps the given asset to USDC (base token) using Uniswap pools
    */
  function swapViaUniswap(address comet, address assetIn, address assetOut, uint256 swapAmount, uint256 amountOutMin) internal returns (uint256) {
      // Safety check, make sure residue balance in protocol is ignored
      if (swapAmount == 0) return 0;

      uint24 poolFee = 3000; // 0.3%
      //address routerAddr = 0xE592427A0AEce92De3Edee1F18E0157C05861564
      address routerAddr = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

      IERC20NonStandard(assetIn).approve(address(routerAddr), swapAmount);
      // Swap asset or received ETH to base asset
      uint256 amountOut = ISwapRouter(routerAddr).exactInputSingle(
          ISwapRouter.ExactInputSingleParams({
              tokenIn: assetIn,
              tokenOut: assetOut,
              fee: poolFee,
              recipient: address(this),
              deadline: block.timestamp,
              amountIn: swapAmount,
              amountOutMinimum: 0,
              sqrtPriceLimitX96: 0
          })
      );

      // we do a manual check against `amountOutMin` (instead of specifying an
      // `amountOutMinimum` in the swap) so we can provide better information
      // in the error message
      if (amountOut < amountOutMin) {
          revert("INSUFFICIENT_OUTPUT_AMOUNT");
      }
      return amountOut;
  }

  // Allow unwrapping Ether
  receive() external payable {}
}
