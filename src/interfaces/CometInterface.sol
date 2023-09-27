// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

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

interface CometInterface {
    function getAssetInfo(uint8 i) external view returns (AssetInfo memory);

    function baseToken() external view returns (address);

    function supply(address asset, uint amount) external view returns (uint256);

    function supplyTo(address dst, address asset, uint amount) external;

    function collateralBalanceOf(address account, address asset) external view returns (uint128);

    function getAssetInfoByAddress(address asset) external view returns (AssetInfo memory);

    function getPrice(address priceFeed) external view returns (uint);

    function borrowBalanceOf(address account) external view returns (uint256);

    function withdraw(address asset, uint amount) external;
  
}