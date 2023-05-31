import { Contract } from '@ethersproject/contracts';
import { Signer } from '@ethersproject/abstract-signer';
import { Provider } from '@ethersproject/abstract-provider';

const networks: { [chainId: number]: string } = {
  5: 'goerli',
  420: 'optimism-goerli',
  421613: 'arbitrum-goerli',
  42161: 'arbitrum'
};

const relayers: { [version: number]: { [network: string]: string } } = {
  1: {
    'goerli': '0x412e71DE37aaEBad89F1441a1d7435F2f8B07270',
    'optimism-goerli': '0x12D356e5C3b05aFB0d0Dbf0999990A6Ec3694e23',
    'arbitrum-goerli': '0x12D356e5C3b05aFB0d0Dbf0999990A6Ec3694e23',
    'arbitrum': '0xC9c445CAAC98B23D1b7439cD75938e753307b2e6',
  }
}

const abi: { [version: number]: string[] } = {
  1: [
    "function quarkAddress25(address) returns (address)",
    "function virtualCode81() returns (bytes)"
  ]
};

export async function getRelayer(signerOrProvider: Signer | Provider): Promise<Contract> {
  let chainId;
  if ('__isProvider' in signerOrProvider && signerOrProvider.__isProvider) {
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
  let network: string;
  if (typeof(chainIdOrNetwork) === 'number') {
    network = networks[chainIdOrNetwork];
    if (!network) {
      throw new Error(`Unsupported Ethereum network: ${chainIdOrNetwork}`);
    }
  } else {
    network = chainIdOrNetwork;
  }

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
