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

contract LeverFlashLoan is IUniswapV3SwapCallback {
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
        uint collateralAmount;
    }

    struct SwapCallbackData {
        uint256 amount0;
        uint256 amount1;
        address payer;
        PoolAddress.PoolKey poolKey;
        Comet comet;
        uint collateralAmount;
    }

    constructor() {}

    // function runSlider(Comet comet, uint8 collateralAssetIndex, uint leverage, uint collateralAmount) exeternal returns (bytes memory) {
    //     uint currenLeverage = 0;
    // }

    function run(
        Comet comet,
        uint8 collateralAssetIndex,
        uint collateralAmount
    ) external returns (bytes memory) {
        AssetInfo memory collateralAsset = comet.getAssetInfo(
            collateralAssetIndex
        );

        // -0.01 ether is a hack because I'm currently too lazy to figure out slippage math
        uint64 borrowCollateralFactor = collateralAsset.borrowCollateralFactor -
            0.01 ether;
        uint24 fee = 500;
        uint scaledFee = (uint(fee) * 1e18) / 1e6;
        uint swapAmount = (borrowCollateralFactor * collateralAmount) /
            (1e18 - scaledFee - borrowCollateralFactor);

        address token0 = collateralAsset.asset;
        address token1 = comet.baseToken();
        uint amount0 = swapAmount;
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
            comet: comet,
            collateralAmount: collateralAmount
        });

        initSwap(params);

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
        supplyAndWithdrawFromCompound(swapCallbackData);

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
        SwapCallbackData memory swapCallbackData
    ) internal {
        // Supply collateral to compound
        address collateralToken = swapCallbackData.poolKey.token1;
        uint collateralAmount = swapCallbackData.amount1 +
            swapCallbackData.collateralAmount;
        Comet comet = swapCallbackData.comet;
        ERC20(collateralToken).approve(address(comet), collateralAmount);
        comet.supply(collateralToken, collateralAmount);

        // Withdraw base asset
        address baseToken = comet.baseToken();
        uint cometBalance = comet.balanceOf(address(this));

        AssetInfo memory collateralAsset = comet.getAssetInfoByAddress(
            collateralToken
        );
        address collateralPriceFeed = collateralAsset.priceFeed;
        uint collateralScale = collateralAsset.scale;
        uint256 collateralPrice = comet.getPrice(collateralPriceFeed);
        uint borrowCollateralFactor = collateralAsset.borrowCollateralFactor;

        uint totalCollateralPrice = (
            ((collateralAmount * collateralPrice) / collateralScale)
        );
        uint usdcPrice = comet.getPrice(comet.baseTokenPriceFeed());
        uint maxBorrowAmount = ((totalCollateralPrice * 1) / usdcPrice) *
            borrowCollateralFactor;
        uint scaledBorrowAmount = (maxBorrowAmount * 1e6) / 1e18;

        comet.withdraw(baseToken, scaledBorrowAmount);
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
        console.log("initSwap");
        console.log("token0:", params.token0);
        console.log("token1:", params.token1);
        console.log("amount0:", params.amount0);
        console.log("amount1:", params.amount1);
        pool.swap(
            address(this),
            true, // 0 -> 1 direction
            -int256(params.amount1), // amount paid in ETH and receive usdc
            TickMath.MIN_SQRT_RATIO + 1, // if opposite direction, TickMath.MAX_SQRT_RATIO - 1, this will break production or MEV not safe
            abi.encode(
                SwapCallbackData({
                    amount0: params.amount0,
                    amount1: params.amount1,
                    payer: msg.sender,
                    poolKey: poolKey,
                    comet: params.comet,
                    collateralAmount: params.collateralAmount
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

struct UserCollateral {
    uint128 balance;
    uint128 _reserved;
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

    function collateralBalanceOf(
        address account,
        address asset
    ) external view returns (uint128);

    function getAssetInfoByAddress(
        address asset
    ) external view returns (AssetInfo memory);

    function userCollateral(
        address account,
        address asset
    ) external view returns (UserCollateral memory);
}
