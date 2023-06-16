import { Contract } from '@ethersproject/contracts';
import { Interface } from '@ethersproject/abi';
import { StaticJsonRpcProvider } from '@ethersproject/providers';
import { Provider } from '@ethersproject/abstract-provider';
import { Signer } from '@ethersproject/abstract-signer';
import { Wallet } from '@ethersproject/wallet';

export type Networks = { [network: string]: NetworkConfig };

export interface NetworkConfig {
  name: string,
  chainId: number,
  signer: Signer,
  provider: Provider,
  beneficiary: string,
  baseFee: BigInt
}

const networkConfigs = {
  'quarknet': {
    chainId: 1,
    rpcUrl: 'https://ethforks.io/@quark',
    baseFee: 1000000000000000n, // 0.001eth
  },
  'goerli': {
    chainId: 5,
    rpcUrl: 'https://goerli-eth.compound.finance',
    baseFee: 1000000000000000n, // 0.001eth
  }
};

export async function getNetworks(pk: string): Promise<Networks> {
  let networks: { [network: string]: NetworkConfig } = {};

  for (let [network, config] of Object.entries(networkConfigs)) {
    let provider = new StaticJsonRpcProvider(config.rpcUrl);
    let wallet = new Wallet(pk).connect(provider);
    let signer: Signer = wallet;

    networks[network] = {
      name: network,
      chainId: config.chainId,
      provider,
      signer,
      beneficiary: await signer.getAddress(),
      baseFee: config.baseFee
    };
  }

  return networks;
}
