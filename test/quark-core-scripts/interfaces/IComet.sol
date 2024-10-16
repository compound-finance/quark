// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

interface IComet {
    function getAssetInfo(uint8 i) external view returns (AssetInfo memory);

    function baseToken() external view returns (address);

    function supply(address asset, uint256 amount) external;

    function withdraw(address asset, uint256 amount) external;

    function balanceOf(address owner) external view returns (uint256);

    function getPrice(address priceFeed) external view returns (uint256);

    function baseTokenPriceFeed() external view returns (address);

    function borrowBalanceOf(address account) external view returns (uint256);

    function collateralBalanceOf(address account, address asset) external view returns (uint128);

    function getAssetInfoByAddress(address asset) external view returns (AssetInfo memory);

    function supplyTo(address dst, address asset, uint256 amount) external;

    function baseScale() external view returns (uint256);

    function isLiquidatable(address account) external view returns (bool);

    function withdrawTo(address to, address asset, uint256 amount) external;

    function withdrawFrom(address src, address to, address asset, uint256 amount) external;

    function supplyFrom(address from, address dst, address asset, uint256 amount) external;

    function allow(address manager, bool isAllowed_) external;
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
