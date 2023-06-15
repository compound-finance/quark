import fs from 'fs';
import arg from 'arg';

import { TransactionRequest } from '@ethersproject/abstract-provider';
import { Interface } from '@ethersproject/abi';
import { Wallet } from '@ethersproject/wallet';
import { hexDataSlice, hexlify } from '@ethersproject/bytes';
import { TrxRequest } from './trxRequest';
import { NetworkConfig, getNetworks } from './network';

import * as Quark from '../../client/src/Quark';

const knownTrxScripts: { [name: string]: (trxCalldata: string) => Promise<Quark.Script.TrxScriptCall> } = {
  'ethcall': (trxCalldata: string) => {
    let input = JSON.parse(trxCalldata) as TransactionRequest | TransactionRequest[];
    let calls: TransactionRequest[];
    if (Array.isArray(input)) {
      calls = input;
    } else {
      calls = [input];
    }

    return Quark.Script.multicallTrxScriptCall(calls, true)
  }
};

async function getTrxScript(trxScript: string, trxCalldata: string): Promise<Quark.Script.TrxScriptCall> {
  if (trxScript.startsWith('0x')) {
    return { trxScript, trxCalldata };
  } else if (trxScript in knownTrxScripts) {
    return await knownTrxScripts[trxScript](trxCalldata);
  } else {
    throw new Error(`Unknown or invalid trx script: ${trxScript}`);
  }
}

async function run(networkName: string, pk: string, nonce: number, reqs: number[], trxScriptArg: string, trxCalldataArg: string, expiry: number) {
  let networks = await getNetworks(pk);
  let network = networks[networkName];
  if (!network) {
    throw new Error(`Unknown or invalid network: ${networkName}`);
  }

  let { trxScript, trxCalldata } = await getTrxScript(trxScriptArg, trxCalldataArg ?? '');

  let signer = new Wallet(pk);
  let account = await signer.getAddress();
  let signedTrxScript = await Quark.Script.signTrxScript(signer, network.chainId, account, nonce, reqs, trxScript, trxCalldata, expiry)

  console.log({signedTrxScript});

  // This is the local check to see if it passes?
  let trxScriptRes = await Quark.Script.callTrxScript(network.provider, signedTrxScript, { from: account });
  console.log({trxScriptRes});

  let trxRequest = {
    network: networkName,
    ...signedTrxScript
  };

  // Test the trxRequest to make sure it works
  let res = await fetch('http://localhost:3000', {
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(trxRequest),
    method: 'POST'
  });
  let json = await res.json();

  console.log({json});
}


const args = arg({
  // Types
  '--network': String,
  '--nonce': Number,
  '--reqs': [Number],
  '--trx-script': String,
  '--trx-calldata': String,
  '--expiry': Number,
  '--private-key': String
});

console.log({args});
let network = args['--network'];
let nonce = args['--nonce'];
let reqs = args['--reqs'];
let trxScript = args['--trx-script'];
let trxCalldata = args['--trx-calldata'];
let expiry = args['--expiry'];
let privateKey = args['--private-key'];

if (!network) {
  // TODO: Provide default?
  throw `Must include --network`;
}

if (nonce === undefined) {
  throw `Must include valid --nonce`;
}

if (reqs === undefined) {
  reqs = [];
}

if (trxScript === undefined) {
  throw `Must include valid --trx-script`;
}

if (trxCalldata === '-') {
  trxCalldata = fs.readFileSync(0, 'utf-8').trim();
}

if (privateKey === undefined) {
  if (process.env['ETH_PRIVATE_KEY']) {
    privateKey = process.env['ETH_PRIVATE_KEY'];
  } else {
    throw `Must include valid --private-key or ETH_PRIVATE_KEY`;
  }
}

if (expiry === undefined) {
  expiry = Date.now() + 86400; // 1 day from now by default
}

run(network, privateKey, nonce, reqs, trxScript, trxCalldata ?? '', expiry);
