// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/console.sol";

contract LeverFlashLoan {
    address constant UNISWAP_ROUTER = address(0);
    address constant UNISWAP_FACTORY = address(0);

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

        return abi.encode();
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
}
