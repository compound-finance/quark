import fs from 'fs';
import arg from 'arg';

import { Interface } from '@ethersproject/abi';
import { Wallet } from '@ethersproject/wallet';
import { hexDataSlice, hexlify } from '@ethersproject/bytes';
import { TrxRequest } from './trxRequest';
import { abi as wrappedScriptAbi, deployedBytecode as wrappedCallScript } from '../../out/WrappedCall.sol/WrappedCall.json'
import { NetworkConfig, getNetworks } from './network';

let quarkScript = new Interface(wrappedScriptAbi);
const trxScriptTypes = {
  TrxScript: [
    { name: 'account', type: 'address' },
    { name: 'nonce', type: 'uint32' },
    { name: 'reqs', type: 'uint32[]' },
    { name: 'trxScript', type: 'bytes' },
    { name: 'trxCalldata', type: 'bytes' },
    { name: 'expiry', type: 'uint256' }
  ]
};

const knownTrxScripts: { [name: string]: string } = {
  'wrapped-call': wrappedCallScript.object
};

function getTrxScript(trxScript: string, trxCalldata: string): [string, string] {
  if (trxScript.startsWith('0x')) {
    return [trxScript, trxCalldata];
  } else if (trxScript in knownTrxScripts) {
    return [knownTrxScripts[trxScript], quarkScript.encodeFunctionData('_exec', [trxCalldata])];
  } else {
    throw new Error(`Unknown or invalid trx script: ${trxScript}`);
  }
}

async function buildTrxScript(
  network: NetworkConfig,
  signer: Wallet,
  account: string,
  nonce: number,
  reqs: number[],
  trxScript: string,
  trxCalldata: string,
  expiry: number): Promise<TrxRequest> {
  // All properties on a domain are optional
  const domain = {
    name: 'Quark',
    version: '0',
    chainId: network.chainId.toString(),
    verifyingContract: network.relayer.address
  };

  // The data to sign
  const trxScriptStruct = {
    account: account,
    nonce: nonce,
    reqs: reqs,
    trxScript: trxScript,
    trxCalldata: trxCalldata,
    expiry: expiry,
  }

  let signature = hexlify(await signer._signTypedData(domain, trxScriptTypes, trxScriptStruct));
  let r = hexDataSlice(signature, 0, 32);
  let s = hexDataSlice(signature, 32, 64);
  let v = hexDataSlice(signature, 64, 65);

  return {
    network: network.name,
    ...trxScriptStruct,
    v,
    r,
    s,
  };
}

async function run(networkName: string, pk: string, nonce: number, reqs: number[], trxScript: string, trxCalldata: string, expiry: number) {
  let networks = await getNetworks(pk);
  let network = networks[networkName];
  if (!network) {
    throw new Error(`Unknown or invalid network: ${networkName}`);
  }

  let signer = new Wallet(pk);
  let account = await signer.getAddress();
  let trxRequest = await buildTrxScript(network, signer, account, nonce, reqs, trxScript, trxCalldata, expiry);
  console.log({trxRequest});

  let trxScriptRes = await network.relayer.callStatic.runTrxScript(
    trxRequest.account,
    trxRequest.nonce,
    trxRequest.reqs,
    trxRequest.trxScript,
    trxRequest.trxCalldata,
    trxRequest.expiry,
    trxRequest.v,
    trxRequest.r,
    trxRequest.s
  );
  console.log({trxScriptRes});

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
let trxScriptArg = args['--trx-script'];
let trxCalldata = args['--trx-calldata'];
let expiry = args['--expiry'];
let privateKey = args['--private-key'];
let trxScript;

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

if (trxScriptArg === undefined) {
  throw `Must include valid --trx-script`;
}

if (trxCalldata === '-') {
  trxCalldata = fs.readFileSync(0, 'utf-8').trim();
}

[trxScript, trxCalldata] = getTrxScript(trxScriptArg, trxCalldata ?? '');

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
