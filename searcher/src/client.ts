import { Interface } from '@ethersproject/abi';
import { Wallet } from '@ethersproject/wallet';
import { hexDataSlice, hexlify } from '@ethersproject/bytes';
import { TrxRequest } from './searcher';
import arg from 'arg';

interface NetworkConfig {
  chainId: number,
  relayer: string
}

const networks: { [network: string]: NetworkConfig } = {
  'quarknet': {
    chainId: 1,
    relayer: '0x687bB6c57915aa2529EfC7D2a26668855e022fAE'
  }
};

const trxScriptTypes = {
  TrxScript: [
    { name: 'account', type: 'address' },
    { name: 'nonce', type: 'uint32' },
    { name: 'reqs', type: 'uint32[]' },
    { name: 'trxScript', type: 'bytes' },
    { name: 'expiry', type: 'uint256' }
  ]
};

async function buildTrxScript(
  network: string,
  signer: Wallet,
  account: string,
  nonce: number,
  reqs: number[],
  trxScript: string,
  expiry: number): Promise<TrxRequest> {
  let networkConfig = networks[network];
  if (!networkConfig) {
    throw new Error(`Unknown or invalid network: ${network}`);
  }

  // All properties on a domain are optional
  const domain = {
    name: 'Quark',
    version: '0',
    chainId: networkConfig.chainId,
    verifyingContract: networkConfig.relayer
  };

  // The data to sign
  const trxScriptStruct = {
    account: account,
    nonce: nonce,
    reqs: reqs,
    trxScript: trxScript,
    expiry: expiry,
  }

  let signature = hexlify(await signer._signTypedData(domain, trxScriptTypes, trxScriptStruct));
  let r = hexDataSlice(signature, 0, 32);
  let s = hexDataSlice(signature, 32, 64);
  let v = hexDataSlice(signature, 64, 65);

  return {
    network,
    ...trxScriptStruct,
    v,
    r,
    s,
  };
}

async function run(network: string, pk: string, nonce: number, reqs: number[], trxScript: string, expiry: number) {
  let signer = new Wallet(pk);
  let account = await signer.getAddress();
  let trxRequest = await buildTrxScript(network, signer, account, nonce, reqs, trxScript, expiry);
  console.log({trxRequest});
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
  '--expiry': Number,
  '--private-key': String
});

console.log({args});
let network = args['--network'];
let nonce = args['--nonce'];
let reqs = args['--reqs'];
let trxScript = args['--trx-script'];
let expiry = args['--expiry'];
let privateKey = args['--private-key'];

if (!network || !networks[network]) {
  throw `Must include valid --network. Networks: ${Object.keys(networks).join(',')}`;
}

if (nonce === undefined) {
  throw `Must include valid --nonce`;
}

if (reqs === undefined) {
  reqs = [];
}

// TODO: Accept this via pipe?
if (trxScript === undefined) {
  throw `Must include valid --trx-script`;
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

run(network, privateKey, nonce, reqs, trxScript, expiry);
