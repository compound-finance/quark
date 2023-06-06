import { Contract } from '@ethersproject/contracts';
import { Signer } from '@ethersproject/abstract-signer';
import { Provider } from '@ethersproject/abstract-provider';
import { abi as relayerAbi } from '../../out/Relayer.sol/Relayer.json'
import { Fragment, JsonFragment } from '@ethersproject/abi';

const networks: { [chainId: number]: string } = {
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
    'goerli': '0xc4f0049a828cd0af222fdbe5adeda9aaf72b7f30',
    'optimism-goerli': '0x66ca95f4ed181c126acbd5aad21767b20d6ad7da',
    'arbitrum-goerli': '0xdde0bf030f2ffceae76817f2da0a14b1e9a87041',
    'arbitrum': '0x66ca95f4ed181c126acbd5aad21767b20d6ad7da',
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
