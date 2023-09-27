// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/console.sol";

import "v3-core/contracts/interfaces/callback/IUniswapV3FlashCallback.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
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
    }

    struct FlashCallbackData {
        uint256 amount0;
        uint256 amount1;
        address payer;
        PoolAddress.PoolKey poolKey;
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

        (token0, token1) = token0 < token1
            ? (token0, token1)
            : (token1, token0);
        (amount0, amount1) = token0 < token1
            ? (amount0, amount1)
            : (amount1, amount0);

        console.log("token0", token0);
        console.log("token1", token1);

        FlashParams memory params = FlashParams({
            token0: token0,
            token1: token1,
            fee: fee,
            amount0: amount0,
            amount1: amount1
        });

        initFlash(params);

        return abi.encode();
    }

    function uniswapV3FlashCallback(
        uint256 fee0,
        uint256 fee1,
        bytes calldata data
    ) external {
        console.log("uniswapV3FlashCallback");
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
        console.log("pool", address(pool));
        pool.flash(
            address(this),
            params.amount0,
            params.amount1,
            abi.encode(
                FlashCallbackData({
                    amount0: params.amount0,
                    amount1: params.amount1,
                    payer: msg.sender,
                    poolKey: poolKey
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
}
