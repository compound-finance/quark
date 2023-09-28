// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../interface/CometInterface.sol";
import "../interface/ISwapRouter.sol";

import "../TransferHelper.sol";
import '../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

contract Rebalance {

  uint128 public constant ASSET1_PRICE_USDC = 1400;
  uint128 public constant ASSET2_PRICE_USDC = 27000;
  uint128 public constant ASSET1_DECIMALS = 18;
  uint128 public constant ASSET2_DECIMALS = 8;

  address public constant UNISWAP_ROUTER =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
  address public constant UNISWAP_V3_POOL = 
  0xCBCdF9626bC03E24f779434178A73a0B4bad62eD;

  uint24 public constant POOL_FEE = 3000; // pool fee = 0.3%

  error InvalidAssetWeight();
  event Portfolio(uint128 asset1BalanceInUSDC, uint128 asset2BalanceInUSDC, uint targetWeight, uint currentWeight);
  event Amounts(int weightDiff, uint128 amountAssetToSellInUSDC);

  event NumberLogs(uint128 collateralBalance, uint128 collateralBalanceRaw);

  function rebalance(address cometAddress, address asset1, address asset2, uint asset1Weight, uint threshold) public {
    if (asset1Weight > 100) { revert InvalidAssetWeight(); }

    // calculate and log current asset portfolio
    uint128 asset1Balance = CometInterface(cometAddress).collateralBalanceOf(msg.sender, asset1);
    uint128 asset2Balance = CometInterface(cometAddress).collateralBalanceOf(msg.sender, asset2);

    uint128 asset1BalanceInUSDC = uint128(asset1Balance * ASSET1_PRICE_USDC / (10 ** ASSET1_DECIMALS));
    uint128 asset2BalanceInUSDC = uint128(asset2Balance * ASSET2_PRICE_USDC / (10 ** ASSET2_DECIMALS));
    uint currentAsset1Weight = uint((asset1BalanceInUSDC * 100) / (asset1BalanceInUSDC + asset2BalanceInUSDC));

    emit Portfolio(asset1BalanceInUSDC, asset2BalanceInUSDC, asset1Weight, currentAsset1Weight);

    int weightDiff = int(currentAsset1Weight) - int(asset1Weight);
    // asset1 grown beyond threshold, so withdraw it, sell it and supply asset2 to protocol
    if (weightDiff  >= int(threshold)) {
      uint128 amountAsset1ToSell = uint128((uint(weightDiff) * (10 ** ASSET1_DECIMALS) * (asset1BalanceInUSDC + asset2BalanceInUSDC)) / (100 * ASSET1_PRICE_USDC));

      // withdraw amountAsset1ToSell from Comet
      CometInterface(cometAddress).withdraw(asset1, amountAsset1ToSell);

      // swap asset1 -> asset2 through Uniswap
      TransferHelper.safeApprove(asset1, UNISWAP_ROUTER, type(uint256).max);

      ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
        tokenIn: asset1,
        tokenOut: asset2,
        fee: POOL_FEE,
        recipient: address(this), // trx script address
        deadline: block.timestamp,
        amountIn: uint256(amountAsset1ToSell),
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
      });
      
      uint256 amountOut = ISwapRouter(UNISWAP_ROUTER).exactInputSingle(params);

      // supply asset2 to protocol on behalf of quark wallet
      if (IERC20(asset2).balanceOf(address(this)) >= amountOut) {
        CometInterface(cometAddress).supplyTo(msg.sender, asset2, amountOut);
      }
    } 
    // asset1 has fallen beyond threshold, need to sell off asset2 and repurchase + resupply asset1
    else if (weightDiff  <= -int(threshold)) {
      uint128 amountAsset2ToSellInUSDC = uint128((uint(weightDiff) * (asset1BalanceInUSDC + asset2BalanceInUSDC)) / 100);

      emit Amounts(weightDiff, amountAsset2ToSellInUSDC);

      // swap with uniswap, asset2 -> asset1
      // amt: amountAsset2ToSellInUSDC / ASSET2_PRICE_USDC


      // supply asset1 to protocol
      // uint amountAsset1ToSupply = uint(amountAsset2ToSellInUSDC / ASSET1_PRICE_USDC);
      // CometInterface(cometAddress).supplyTo(msg.sender, asset1, amountAsset1ToSupply);
    } else {
      emit Amounts(weightDiff, 0);
    }

    // calculate and log new asset portfolio
    uint128 newAsset1Balance = CometInterface(cometAddress).collateralBalanceOf(msg.sender, asset1);
    uint128 newAsset2Balance = CometInterface(cometAddress).collateralBalanceOf(msg.sender, asset2);

    uint128 newAsset1BalanceInUSDC = uint128(newAsset1Balance * ASSET1_PRICE_USDC / (10 ** ASSET1_DECIMALS));
    uint128 newAsset2BalanceInUSDC = uint128(newAsset2Balance * ASSET2_PRICE_USDC / (10 ** ASSET2_DECIMALS));
    uint newAsset1Weight = uint((newAsset1BalanceInUSDC * 100) / (newAsset1BalanceInUSDC + newAsset2BalanceInUSDC));

    emit Portfolio(newAsset1BalanceInUSDC, newAsset2BalanceInUSDC, asset1Weight, newAsset1Weight);
  }

  receive() external payable {}
}