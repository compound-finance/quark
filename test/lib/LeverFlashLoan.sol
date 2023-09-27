// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/console.sol";

import "v3-core/contracts/interfaces/callback/IUniswapV3FlashCallback.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "solmate/tokens/ERC20.sol";
import "./PoolAddress.sol";

contract LeverFlashLoan is IUniswapV3FlashCallback {
    address constant UNISWAP_ROUTER = address(0);
    address constant UNISWAP_FACTORY =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;

    struct FlashParams {
        address token0;
        address token1;
        uint24 fee;
        uint256 amount0;
        uint256 amount1;
        Comet comet;
    }

    struct FlashCallbackData {
        uint256 amount0;
        uint256 amount1;
        address payer;
        PoolAddress.PoolKey poolKey;
        Comet comet;
    }

    constructor() {}

    function run(
        Comet comet,
        uint8 collateralAssetIndex,
        uint collateralAmount
    ) external returns (bytes memory) {
        AssetInfo memory collateralAsset = comet.getAssetInfo(
            collateralAssetIndex
        );
        uint64 borrowCollateralFactor = collateralAsset.borrowCollateralFactor;
        uint flashLoanAmount = (collateralAmount * borrowCollateralFactor) /
            (1e18 - borrowCollateralFactor);

        address token0 = collateralAsset.asset;
        address token1 = comet.baseToken();
        uint amount0 = flashLoanAmount;
        uint amount1 = 0;

        uint24 fee = 500;

        (token0, token1, amount0, amount1) = token0 < token1
            ? (token0, token1, amount0, amount1)
            : (token1, token0, amount1, amount0);

        FlashParams memory params = FlashParams({
            token0: token0,
            token1: token1,
            fee: fee,
            amount0: amount0,
            amount1: amount1,
            comet: comet
        });

        initFlash(params);

        return abi.encode();
    }

    function uniswapV3FlashCallback(
        uint256 fee0,
        uint256 fee1,
        bytes calldata data
    ) external {
        // console.log("fee0", fee0);
        // console.log("fee1", fee1);
        // console.logBytes(data);
        FlashCallbackData memory flashCallbackData = abi.decode(
            data,
            (FlashCallbackData)
        );
        console.log("amount0", flashCallbackData.amount0);
        console.log("amount1", flashCallbackData.amount1);
        // console.log("payer", flashCallbackData.payer);
        console.log("poolKey.token0", flashCallbackData.poolKey.token0);
        console.log("poolKey.token1", flashCallbackData.poolKey.token1);

        console.log(
            "Token0 balance:",
            ERC20(flashCallbackData.poolKey.token0).balanceOf(address(this))
        );
        console.log(
            "Token1 balance:",
            ERC20(flashCallbackData.poolKey.token1).balanceOf(address(this))
        );

        // Supply collateral to compound
        address collateralToken = flashCallbackData.poolKey.token1;
        uint collateralAmount = flashCallbackData.amount1;
        Comet comet = flashCallbackData.comet;
        ERC20(collateralToken).approve(
            address(comet),
            flashCallbackData.amount1
        );
        comet.supply(collateralToken, flashCallbackData.amount1);

        // Withdraw base asset
        address baseToken = comet.baseToken();
        uint cometBalance = comet.balanceOf(address(this));
        console.log("cometBalance:", cometBalance);
        uint usdcBalance = ERC20(baseToken).balanceOf(address(this));
        console.log("usdcBalance:", usdcBalance);

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

        // Swap base token back to collateral token

        // Repay flash loan
    }

    function initFlash(FlashParams memory params) internal {
        PoolAddress.PoolKey memory poolKey = PoolAddress.PoolKey({
            token0: params.token0,
            token1: params.token1,
            fee: params.fee
        });
        IUniswapV3Pool pool = IUniswapV3Pool(
            PoolAddress.computeAddress(UNISWAP_FACTORY, poolKey)
        );

        pool.flash(
            address(this),
            params.amount0,
            params.amount1,
            abi.encode(
                FlashCallbackData({
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

    function getAssetInfoByAddress(
        address asset
    ) external view returns (AssetInfo memory);

    function baseTokenPriceFeed() external view returns (address);
}
