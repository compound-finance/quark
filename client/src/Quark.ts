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

export const UINT256_MAX = new Uint256("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");

const v1code = '0x60008080808080335af115606d5760173d81810192605f601d856070565b938383863e60405180156066575b601281602060059301604052602060c682395195600660a9893960506001820189608a565b8088019360af8539019101608a565b5533600155f35b506060602b565b80fd5b906040519182156082575b8201604052565b60609250607b565b9060ff60039180601d1a600185015380601e1a60028501531691015356fe62000000565bfe5b600254620000005760016002556005565b600054ff';

const initCodes: { [version: number]: { [network: string]: string } } = {
  1: {
    'goerli': v1code,
    'optimism-goerli': v1code,
    'arbitrum-goerli': v1code,
    'arbitrum': v1code,
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
