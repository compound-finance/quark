// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IErc20 {
  function approve(address spender, uint256 amount) external returns (bool);
}

interface IComet {
  function supply(address asset, uint amount) external;
  function withdraw(address asset, uint amount) external;
}

contract Comet {
  IErc20 constant usdc = IErc20(0x07865c6E87B9F70255377e024ace6630C1Eaa37F);
  IErc20 constant comp = IErc20(0x3587b2F7E0E2D6166d6C14230e7Fe160252B0ba4);
  IErc20 constant wbtc = IErc20(0xAAD4992D949f9214458594dF92B44165Fb84dC19);
  IComet constant comet = IComet(0x3EE77595A8459e93C2888b13aDB354017B198188);
  IFauceteer constant fauceteer = IFauceteer(0x5B0156A396BdFc2eb814D945Ac99C40A0F8592B2);

  function supplyAndBorrow() external {
    comp.approve(address(comet), 100e18);
    wbtc.approve(address(comet), 100e6);

    comet.supply(address(comp), 100e18);

    comet.withdraw(address(usdc), 101e6);
  }
}
