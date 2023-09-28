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

  uint24 public constant POOL_FEE = 3000; // pool fee = 0.3%

  error InvalidAssetWeight();
  error NotRebalanceable(); // revert if not rebalanceable, so we can sign trx and keep submitting it

  event Portfolio(uint128 asset1BalanceInUSDC, uint128 asset2BalanceInUSDC, uint targetWeight, uint currentWeight);

  function rebalance(address cometAddress, address asset1, address asset2, uint asset1Weight, uint threshold) public {
    if (asset1Weight > 100) { revert InvalidAssetWeight(); }

    // calculate and log current asset portfolio
    (uint128 asset1BalanceInUSDC, uint128 asset2BalanceInUSDC) = _getAssetBalancesInUSDC(cometAddress, asset1, asset2);
    uint currentAsset1Weight = uint((asset1BalanceInUSDC * 100) / (asset1BalanceInUSDC + asset2BalanceInUSDC));
    emit Portfolio(asset1BalanceInUSDC, asset2BalanceInUSDC, asset1Weight, currentAsset1Weight);

    int weightDiff = int(currentAsset1Weight) - int(asset1Weight);
    // asset1 grown beyond threshold, so withdraw it, sell it and supply asset2 to protocol
    if (weightDiff  >= int(threshold)) {
      uint128 amountAsset1ToSell = uint128((uint(weightDiff) * (10 ** ASSET1_DECIMALS) * (asset1BalanceInUSDC + asset2BalanceInUSDC)) / (100 * ASSET1_PRICE_USDC));

      // withdraw amountAsset1ToSell from Comet
      CometInterface(cometAddress).withdraw(asset1, amountAsset1ToSell);

      // swap asset1 -> asset2 through Uniswap
      uint256 amountOut = _swapAssets(asset1, asset2, uint256(amountAsset1ToSell));

      // supply asset2 to protocol on behalf of quark wallet
      _supplyToProtocol(cometAddress, asset2, amountOut);
    } 
    // asset1 has fallen beyond threshold, need to sell off asset2 and repurchase + resupply asset1
    else if (weightDiff < 0 && (uint(weightDiff) >= threshold)) {
      uint128 amountAsset2ToSell = uint128((uint256(weightDiff * -1) * (10 ** ASSET2_DECIMALS) * (asset1BalanceInUSDC + asset2BalanceInUSDC)) / (100 * ASSET2_PRICE_USDC));
      // withdraw amountAsset2ToSell from Comet
      CometInterface(cometAddress).withdraw(asset2, amountAsset2ToSell);

      // swap asset2 -> asset1 through Uniswap
      uint256 amountOut = _swapAssets(asset2, asset1, uint256(amountAsset2ToSell));

      // supply asset1 to protocol on behalf of quark wallet
      _supplyToProtocol(cometAddress, asset1, amountOut);
    } else {
      revert NotRebalanceable();
    }

    // calculate and log new asset portfolio
    (uint128 newAsset1BalanceInUSDC, uint128 newAsset2BalanceInUSDC) = _getAssetBalancesInUSDC(cometAddress, asset1, asset2);
    uint newAsset1Weight = uint((newAsset1BalanceInUSDC * 100) / (newAsset1BalanceInUSDC + newAsset2BalanceInUSDC));
    emit Portfolio(newAsset1BalanceInUSDC, newAsset2BalanceInUSDC, asset1Weight, newAsset1Weight);
  }

  function _swapAssets(address tokenIn, address tokenOut, uint256 amountIn) internal returns (uint256) {
    TransferHelper.safeApprove(tokenIn, UNISWAP_ROUTER, type(uint256).max);

    ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
      tokenIn: tokenIn,
      tokenOut: tokenOut,
      fee: POOL_FEE,
      recipient: address(this), // trx script address
      deadline: block.timestamp,
      amountIn: amountIn,
      amountOutMinimum: 0,
      sqrtPriceLimitX96: 0
    });

    return ISwapRouter(UNISWAP_ROUTER).exactInputSingle(params);
  }

  function _getAssetBalancesInUSDC(address cometAddress, address asset1, address asset2) internal view returns (uint128, uint128) {
    uint128 asset1Balance = CometInterface(cometAddress).collateralBalanceOf(msg.sender, asset1);
    uint128 asset2Balance = CometInterface(cometAddress).collateralBalanceOf(msg.sender, asset2);

    uint128 asset1BalanceInUSDC = uint128(asset1Balance * ASSET1_PRICE_USDC / (10 ** ASSET1_DECIMALS));
    uint128 asset2BalanceInUSDC = uint128(asset2Balance * ASSET2_PRICE_USDC / (10 ** ASSET2_DECIMALS));

    return (asset1BalanceInUSDC, asset2BalanceInUSDC);
  }

  function _supplyToProtocol(address cometAddress, address asset, uint256 amount) internal {
    if (IERC20(asset).balanceOf(address(this)) >= amount) {
      CometInterface(cometAddress).supplyTo(msg.sender, asset, amount);
    }
  }

  receive() external payable {}
}