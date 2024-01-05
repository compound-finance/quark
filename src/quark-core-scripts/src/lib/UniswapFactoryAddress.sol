// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

library UniswapFactoryAddress {
    // Reference: https://docs.uniswap.org/contracts/v3/reference/deployments
    address internal constant MAINNET = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address internal constant CELO = 0xAfE208a311B21f13EF87E33A90049fC17A7acDEc;
    address internal constant BNB = 0xdB1d10011AD0Ff90774D0C6Bb92e5C5c8b4461F7;
    address internal constant BASE = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;

    error UnrecognizedChain(uint256);

    function getAddress() internal view returns (address) {
        if (block.chainid == 1) return MAINNET; // Ethereum mainnet
        if (block.chainid == 10) return MAINNET; // Optimism mainnet
        if (block.chainid == 42161) return MAINNET; // Arbitrum mainnet
        if (block.chainid == 137) return MAINNET; // Polygon mainnet
        if (block.chainid == 5) return MAINNET; // Goerli testnet
        if (block.chainid == 56) return BNB; // Binance Smart Chain mainnet
        if (block.chainid == 8453) return BASE; // Base mainnet
        if (block.chainid == 42220) return CELO; // Celo mainnet
        revert UnrecognizedChain(block.chainid);
    }
}
