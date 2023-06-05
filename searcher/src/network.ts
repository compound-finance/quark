import { Contract } from '@ethersproject/contracts';
import { Interface } from '@ethersproject/abi';
import { StaticJsonRpcProvider } from '@ethersproject/providers';
import { Provider } from '@ethersproject/abstract-provider';
import { Signer } from '@ethersproject/abstract-signer';
import { Wallet } from '@ethersproject/wallet';
import { abi as relayerAbi } from '../../out/Relayer.sol/Relayer.json';

export type Networks = { [network: string]: NetworkConfig };

export interface NetworkConfig {
  name: string,
  chainId: number,
  relayer: Contract,
  signer: Signer,
  provider: Provider,
  recipient: string,
  payToken: string,
  payTokenOracle: string,
  expectedWindfall: number,
}

const networkConfigs = {
  'quarknet': {
    name: 'quarknet',
    chainId: 1,
    relayer: '0x6DcBc91229d812910b54dF91b5c2b592572CD6B0',
    rpcUrl: 'https://ethforks.io/@quark',
    payToken: '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48',
    payTokenOracle: '0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419',
    expectedWindfall: 1e6, // $1.00
  }
};

export async function getNetworks(pk: string): Promise<Networks> {
  let networks: { [network: string]: NetworkConfig } = {};

  for (let [network, config] of Object.entries(networkConfigs)) {
    let provider = new StaticJsonRpcProvider(config.rpcUrl);
    let wallet = new Wallet(pk).connect(provider);
    let signer: Signer = wallet;
    let relayer = new Contract(
      config.relayer,
      relayerAbi,
      signer
    );

    networks[network] = {
      name: config.name,
      chainId: config.chainId,
      relayer,
      provider,
      signer,
      recipient: await signer.getAddress(),
      payToken: config.payToken,
      payTokenOracle: config.payTokenOracle,
      expectedWindfall: config.expectedWindfall
    };
  }

  return networks;
}