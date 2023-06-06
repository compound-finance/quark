import { Uint256 } from './Value';
export { Address, Bool, Bytes, Uint256 } from './Value';
export { exec } from './Execute';
export { getRelayer, Relayer } from './Relayer';
export { wrap, invoke, readUint256, readAddress } from './Invocation';
export { pipeline } from './Pipeline';
export { Action, buildAction, pipe, pop } from './Action';
export { Command, prepare } from './Command';
export { buildSol, buildYul } from './Compiler';
import { getNetwork, relayers } from './Relayer';
import { keccak256 } from '@ethersproject/keccak256';
export * as Script from './Script';
import { bytecode as quarkBytecode } from '../../out/Quark.yul/Quark.json'

export const UINT256_MAX = new Uint256("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");

const bytecodeV1 = quarkBytecode.object;

const initCodes: { [version: number]: { [network: string]: string } } = {
  1: {
    'goerli': bytecodeV1,
    'optimism-goerli': bytecodeV1,
    'arbitrum-goerli': bytecodeV1,
    'arbitrum': bytecodeV1,
  }
};

export function quarkAddress(address: string, chainIdOrNetwork: string | number, version = 1): string {
  let network = getNetwork(chainIdOrNetwork);
  let initCode = initCodes[version]?.[network];
  let relayerAddress = relayers[version]?.[network];

  if (!initCode) {
    throw new Error(`No known Quark deployment on network=${network}, version=${version} [missing init code]`);
  }

  if (!relayerAddress) {
    throw new Error(`No known Quark deployment on network=${network}, version=${version} [missing address]`);
  }

  let salt = `0x0000000000000000000000000000000000000000000000000000000000000000`;
  let value = '0x' + [
    '0xff',
    relayerAddress,
    salt,
    keccak256(initCode + '000000000000000000000000' + address.slice(2))
  ].map((x) => x.slice(2)).join('');
  return '0x' + keccak256(value).slice(26);
}
