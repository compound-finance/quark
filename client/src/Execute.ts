import { Contract } from '@ethersproject/contracts';
import { Signer } from '@ethersproject/abstract-signer';
import type { Command } from './Command';
import { getRelayer } from './Relayer';

export async function exec(signerOrRelayer: Signer | Contract, command: Command, txOpts = {}): Promise<any> {
  let relayer: Contract;

  if ('_isSigner' in signerOrRelayer && signerOrRelayer._isSigner) {
    relayer = await getRelayer(signerOrRelayer as unknown as Signer);
  } else {
    relayer = signerOrRelayer as Contract;
  }

  let relayerAddress: string = relayer.address;
  if (!relayerAddress) {
    throw new Error(`Invalid relayer: ${JSON.stringify(signerOrRelayer)}`);
  }

  let signer: Signer = relayer.signer;
  if (!(signer && '_isSigner' in signerOrRelayer && signerOrRelayer._isSigner)) {
    if ('__isProvider' in signerOrRelayer) {
      throw new Error(`Must pass in Signer to execute Quark trx, received provider: ${JSON.stringify(signer)}`);  
    } else {
      throw new Error(`Invalid signer: ${JSON.stringify(signer)}`);
    }
  }

  return signer.sendTransaction({
    to: relayerAddress,
    data: command.bytecode,
    ...txOpts
  })
}
