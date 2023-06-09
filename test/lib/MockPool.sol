// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../src/scripts/FlashMulticall.sol";

interface MockPoolCallback {
    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata data) external;
}

interface MockErc20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address acct) external returns (uint256);
}

contract MockPool is FlashMulticallUniswapPool {
    error InsufficientRepay(address token);

    address immutable public token0;
    address immutable public token1;
    uint256 immutable fee;

    constructor(address token0_, address token1_, uint256 fee_) {
        token0 = token0_;
        token1 = token1_;
        fee = fee_;
    }

    function flash(
        address recipient,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external {
        uint256 fee0 = amount0 * fee / 10000; // bps
        uint256 balance0 = MockErc20(token0).balanceOf(address(this));
        uint256 balanceExp0 = balance0 + fee0;
        if (amount0 > 0) {
            require(MockErc20(token0).transfer(recipient, amount0));
        }

        uint256 fee1 = amount1 * fee / 10000; // bps
        uint256 balance1 = MockErc20(token1).balanceOf(address(this));
        uint256 balanceExp1 = balance1 + fee1;
        if (amount1 > 0) {
            require(MockErc20(token1).transfer(recipient, amount1));
        }

        MockPoolCallback(recipient).uniswapV3FlashCallback(fee0, fee1, data);

        uint256 balancePost0 = MockErc20(token0).balanceOf(address(this));
        if (balancePost0 < balanceExp0) {
            revert InsufficientRepay(token0);
        }

        uint256 balancePost1 = MockErc20(token1).balanceOf(address(this));
        if (balancePost1 < balanceExp1) {
            revert InsufficientRepay(token1);
        }
    }
}
