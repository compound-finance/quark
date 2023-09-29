// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/console.sol";

import "v3-core/contracts/interfaces/callback/IUniswapV3FlashCallback.sol";
import "v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "v3-core/contracts/libraries/TickMath.sol";
import "v3-periphery/interfaces/ISwapRouter.sol";
import "solmate/tokens/ERC20.sol";
import "./PoolAddress.sol";

contract LeverFlashLoanAdjustable is IUniswapV3SwapCallback {
    address constant UNISWAP_ROUTER =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant UNISWAP_FACTORY =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;

    struct SwapParams {
        address token0;
        address token1;
        uint24 fee;
        uint256 amount0;
        uint256 amount1;
        Comet comet;
    }

    struct SwapCallbackData {
        uint256 amount0;
        uint256 amount1;
        address payer;
        PoolAddress.PoolKey poolKey;
        Comet comet;
    }

    constructor() {}

    function runSlider(Comet comet, uint leverage) external returns (bytes memory) {
        // address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        // address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        AssetInfo memory collateralAsset = comet.getAssetInfoByAddress(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        // AssetInfo memory baseAsset = comet.getAssetInfoByAddress(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

        uint collateralAssetValue = comet.collateralBalanceOf(address(this), 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) * comet.getPrice(collateralAsset.priceFeed) / collateralAsset.scale;
        uint debtValue = comet.borrowBalanceOf(address(this)) * comet.getPrice(comet.baseTokenPriceFeed()) / comet.baseScale();

        // leverage in a form of 100 - X00
        uint currenLeverage = (collateralAssetValue * 1e2) / (collateralAssetValue - debtValue);
        uint24 fee = 500;

        if ( leverage > currenLeverage){
            // Apply leverage equation to get the amount of baseAsset to borrow
            // dA = (LA-LD-A) / ((1 - f + Lf)
            // With scales with leverage with X00 instead of %, and fee in 500 instead of 0.05%
            // dA =((L*A-L*D-100*A) * 1000000) / (1000000*100 - f*100 + L*f )
            uint assetAcquireInUSD = 
                ((leverage * collateralAssetValue - leverage * debtValue - 100 * collateralAssetValue) * 1e6) 
                / (1e8 - fee * 100 + leverage * fee);
            uint assetToAcquire = assetAcquireInUSD * 1e18 / comet.getPrice(collateralAsset.priceFeed);


            address token0 = collateralAsset.asset;
            address token1 = comet.baseToken();
            uint amount0 = assetToAcquire;
            uint amount1 = 0;

            (token0, token1, amount0, amount1) = token0 < token1
                ? (token0, token1, amount0, amount1)
                : (token1, token0, amount1, amount0);

            SwapParams memory params = SwapParams({
                token0: token0,
                token1: token1,
                fee: fee,
                amount0: amount0,
                amount1: amount1,
                comet: comet
            });

            initSwap(params);

        } else if (leverage < currenLeverage) {
            // Apply leverage equation to get the amount of baseAsset to repay
            // dA = (A + LD - LE) / (1 - Lf)
            // with scales
            // dA = (100*A + L*D - L*A) * 1000000 / (100*1000000 - L*f)
            uint assetToSellInUSD = 
                (100 * collateralAssetValue + leverage * debtValue - leverage * collateralAssetValue) * 1e6
                / (1e8 - leverage * fee);
            // uint assetToSell = assetToSellInUSD * 1e18 / collateralAssetPrice;
            uint usdcToGet = assetToSellInUSD * 1e6 / comet.getPrice(comet.baseTokenPriceFeed());


            address token0 = collateralAsset.asset;
            address token1 = comet.baseToken();
            uint amount0 = 0;
            uint amount1 = usdcToGet;

            (token0, token1, amount0, amount1) = token0 < token1
                ? (token0, token1, amount0, amount1)
                : (token1, token0, amount1, amount0);

            SwapParams memory params = SwapParams({
                token0: token0,
                token1: token1,
                fee: fee,
                amount0: amount0,
                amount1: amount1,
                comet: comet
            });

            initSwap(params);
        } else {
            // Do nothing
        }
    


        return abi.encode();
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        SwapCallbackData memory swapCallbackData = abi.decode(
            data,
            (SwapCallbackData)
        );
        Comet comet = swapCallbackData.comet;

        supplyAndWithdrawFromCompound(swapCallbackData, amount0Delta, amount1Delta);


        if (amount0Delta > 0) {
            ERC20(swapCallbackData.poolKey.token0).transfer(
                msg.sender,
                uint256(amount0Delta)
            );
        } else if (amount1Delta > 0) {
            ERC20(swapCallbackData.poolKey.token1).transfer(
                msg.sender,
                uint256(amount1Delta)
            );
        }
    }

    function supplyAndWithdrawFromCompound(
        SwapCallbackData memory swapCallbackData, 
        int256 amount0Delta,
        int256 amount1Delta
    ) internal {
        Comet comet = swapCallbackData.comet;
        if (swapCallbackData.amount0 > 0){
            // supply token0
            ERC20(swapCallbackData.poolKey.token0).approve(address(comet), swapCallbackData.amount0);
            comet.supply(swapCallbackData.poolKey.token0, swapCallbackData.amount0);
        } else if (swapCallbackData.amount1 > 0){
            // supply token1
            ERC20(swapCallbackData.poolKey.token1).approve(address(comet), swapCallbackData.amount1);
            comet.supply(swapCallbackData.poolKey.token1, swapCallbackData.amount1);
        } else {
            revert("No supply");
        }

        if (amount0Delta > 0){
            // withdraw token0
            comet.withdraw(swapCallbackData.poolKey.token0, uint256(amount0Delta));
        } else if (amount1Delta > 0){
            // withdraw token1
            comet.withdraw(swapCallbackData.poolKey.token0, uint256(amount1Delta));
        } else {
            revert("No withdraw");
        }
    }

    function initSwap(SwapParams memory params) internal {
        PoolAddress.PoolKey memory poolKey = PoolAddress.PoolKey({
            token0: params.token0,
            token1: params.token1,
            fee: params.fee
        });
        IUniswapV3Pool pool = IUniswapV3Pool(
            PoolAddress.computeAddress(UNISWAP_FACTORY, poolKey)
        );

        pool.swap(
            address(this),
            params.amount1 > params.amount0 ? true : false, // 0 -> 1 direction
            params.amount1 > params.amount0 ? -int256(params.amount1) : -int256(params.amount0), // amount paid in ETH and receive usdc
            params.amount1 > params.amount0 ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1, // if opposite direction, TickMath.MAX_SQRT_RATIO - 1, this will break production or MEV not safe
            abi.encode(
                SwapCallbackData({
                    amount0: params.amount0,
                    amount1: params.amount1,
                    payer: msg.sender,
                    poolKey: poolKey,
                    comet: params.comet
                })
            )
        );
    }

    fallback() external payable {}

    receive() external payable {}
}

struct AssetInfo {
    uint8 offset;
    address asset;
    address priceFeed;
    uint64 scale;
    uint64 borrowCollateralFactor;
    uint64 liquidateCollateralFactor;
    uint64 liquidationFactor;
    uint128 supplyCap;
}

interface Comet {
    function getAssetInfo(uint8 i) external view returns (AssetInfo memory);

    function baseToken() external view returns (address);

    function supply(address asset, uint amount) external;

    function withdraw(address asset, uint amount) external;

    function balanceOf(address owner) external view returns (uint256);

    function getPrice(address priceFeed) external view returns (uint256);

    function baseTokenPriceFeed() external view returns (address);

    function borrowBalanceOf(address account) external view returns (uint256);

    function collateralBalanceOf(address account, address asset) external view returns (uint128);

    function getAssetInfoByAddress(address asset) external view returns (AssetInfo memory);

    function supplyTo(address dst, address asset, uint amount) external;

    function baseScale() external view returns (uint);


}
