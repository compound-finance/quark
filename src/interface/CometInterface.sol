// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

/**
 * @title Compound's Comet Interface
 * @notice An efficient monolithic money market protocol
 * @author Compound
 */
abstract contract CometInterface {
    function collateralBalanceOf(address account, address asset) virtual external view returns (uint128);
    function supplyFrom(address from, address dst, address asset, uint amount) virtual external;
    function supplyTo(address dst, address asset, uint amount) virtual external;
    function withdraw(address asset, uint amount) virtual external;
}
