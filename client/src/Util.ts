import { Value, Bytes } from './Value';
import { keccak256 } from '@ethersproject/keccak256';
import { toUtf8Bytes } from '@ethersproject/strings';

export function callSig(abi: string): Value<Bytes> {
  return new Bytes(keccak256(toUtf8Bytes(abi)).slice(0, 10));
}
