import { Contract } from '@ethersproject/contracts';
import { Signer } from '@ethersproject/abstract-signer';
import { Provider } from '@ethersproject/abstract-provider';
import { abi as relayerAbi } from '../../out/Relayer.sol/Relayer.json'
import { Fragment, JsonFragment } from '@ethersproject/abi';

const networks: { [chainId: number]: string } = {
  1: 'mainnet',
  5: 'goerli',
  420: 'optimism-goerli',
  421613: 'arbitrum-goerli',
  42161: 'arbitrum'
};

export function getNetwork(chainIdOrNetwork: number | string) : string {
  let network: string;
  if (typeof(chainIdOrNetwork) === 'number') {
    let network = networks[chainIdOrNetwork];
    if (!network) {
      throw new Error(`Unsupported Ethereum network: ${chainIdOrNetwork}`);
    }
    return network;
  } else {
    return chainIdOrNetwork;
  }
}

export const relayers: { [version: number]: { [network: string]: string } } = {
  1: {
    'goerli': '0xE2F373f64f7b60a82a4aC1aF1543f9e9eBa38fE1', // vm one
    'optimism-goerli': '0x66ca95f4ed181c126acbd5aad21767b20d6ad7da',
    'arbitrum-goerli': '0xdde0bf030f2ffceae76817f2da0a14b1e9a87041',
    'arbitrum': '0xcc3b9A2510f828c952e67C024C3dE60839Aca842', // local change
    'mainnet': '0x687bB6c57915aa2529EfC7D2a26668855e022fAE' // local change
  }
}

export const vms: { [version: number]: { [network: string]: string } } = {
  1: {
    'goerli': '0x5bfBa3B17124c4EA75FB8BFf8af7697609d70ED7',
    'arbitrum': '0x3A5e5bF04d05aca69eEFC63CD832eBec49A6314a', // local change
    'mainnet': '0x13E0Ece0Fa1Ff3795947FaB553dA5DaB6c9eF470', // local change
  }
}

export const abi: { [version: number]: ReadonlyArray<Fragment | JsonFragment | string> } = {
  1: relayerAbi
};

export async function getRelayer(signerOrProvider: Signer | Provider): Promise<Contract> {
  let chainId;
  if ( ( '__isProvider' in signerOrProvider && signerOrProvider.__isProvider )
       || ( '_isProvider' in signerOrProvider && signerOrProvider._isProvider ) ) {
    chainId = (await (signerOrProvider as unknown as Provider).getNetwork()).chainId;
  } else if ('_isSigner' in signerOrProvider && signerOrProvider._isSigner) {
    chainId = (await (signerOrProvider as unknown as Signer).getChainId());
  } else {
    throw new Error(`Invalid signer or pvodier: ${signerOrProvider}`);
  }
  let version = 1;

  return Relayer(signerOrProvider, chainId, version);
}

export function Relayer(signerOrProvider: Signer | Provider, chainIdOrNetwork: number | string, version: number = 1): Contract {
  let network = getNetwork(chainIdOrNetwork);

  let relayerAbi = abi[version];
  if (!relayerAbi) {
    throw new Error(`Invalid Relayer version: ${version}`);
  }

  let relayerAddress = relayers[version]?.[network];
  if (!relayerAddress) {
    throw new Error(`No Relayer available for network=${network}, version=${version}`)
  }

  return new Contract(relayerAddress, relayerAbi, signerOrProvider)
}
