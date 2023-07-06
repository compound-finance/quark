import { Contract } from '@ethersproject/contracts';
import { Signer } from '@ethersproject/abstract-signer';
import { Provider } from '@ethersproject/abstract-provider';
import { abi as relayerAbi } from '../../out/Relayer.sol/Relayer.json'
import { Fragment, JsonFragment } from '@ethersproject/abi';
import * as deployments from '../../deployments.json';

let deploymentsLocal;
try {
  deploymentsLocal = import('../../deployments.local.json');
  // Override with any local settings
  for (let [n, v] of Object.entries(deploymentsLocal)) {
    (deployments as any)[n] = v;
  }
} catch (e) {}

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
  1:
    Object.fromEntries(
      Object
        .entries(deployments)
        .filter(([n, v]) => 'Relayer' in v && v['Relayer'] !== null)
        .map(([n, v]) => [n, v['Relayer']])
    )
};

export const abi: { [version: number]: ReadonlyArray<Fragment | JsonFragment | string> } = {
  1: relayerAbi
};

export const initCodes: { [version: number]: { [network: string]: string } } = {
  1: Object.fromEntries(
      Object
        .entries(deployments)
        .filter(([n, v]) => 'RelayerBytecode' in v && v['RelayerBytecode'] !== null)
        .map(([n, v]) => [n, v['RelayerBytecode']])
    )
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

export function getRelayerBySigner(signer: Signer, chainId: number): Contract {
  let version = 1;

  return Relayer(signer, chainId, version);
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
