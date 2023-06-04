import Fastify from 'fastify'
import { Contract } from '@ethersproject/contracts';
import { Interface } from '@ethersproject/abi';
import { StaticJsonRpcProvider } from '@ethersproject/providers';
import { Provider } from '@ethersproject/abstract-provider';
import { Signer } from '@ethersproject/abstract-signer';
import { Wallet } from '@ethersproject/wallet';
import { abi as relayerAbi } from '../../out/Relayer.sol/Relayer.json';
// TODO: Get this script
import { bytecode as searcherScript } from '../../out/PaySearcher.yul/PaySearcher.json'
import { TrxRequest } from './searcher.ts';

interface NetworkConfig {
  relayer: Contract,
  signer: Signer,
  provider: Provider,
  recipient: string,
  payToken: string,
  payTokenOracle: string,
  expectedWindfall: number,
}

const networkConfigs = {
  'quarknet': {
    relayer: '0x687bB6c57915aa2529EfC7D2a26668855e022fAE',
    rpcUrl: 'https://ethforks.io/@quark',
    payToken: '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48',
    payTokenOracle: '0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419',
    expectedWindfall: 1e6, // $1.00
  }
};

const networks: { [network: string]: NetworkConfig } = {};

const relayerInterface = new Interface(relayerAbi);

async function run() {
  // All properties on a domain are optional
  const domain = {
    name: 'Ether Mail',
    version: '1',
    chainId: 1,
    verifyingContract: '0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC'
  };

  // The named list of all type definitions
  const types = {
    Person: [
        { name: 'name', type: 'string' },
        { name: 'wallet', type: 'address' }
    ],
    Mail: [
        { name: 'from', type: 'Person' },
        { name: 'to', type: 'Person' },
        { name: 'contents', type: 'string' }
    ]
  };

  // The data to sign
  const value = {
    from: {
        name: 'Cow',
        wallet: '0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826'
    },
    to: {
        name: 'Bob',
        wallet: '0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB'
    },
    contents: 'Hello, Bob!'
  };

  let signature = await signer._signTypedData(domain, types, value);

  let res = fetch('http://localhost:3000', {
    headers: {
      'Content-Type': 'application/json',
      body: JSON.stringify(trxRequest)
    }
  });
  let json = await res.json();

  console.log({json});
}
function getTrxRequest(req: object): TrxRequest {
  if (!('network' in req)) {
    throw new Error(`Missing required key \`network\``);
  }

  if (typeof(req.network) !== 'string' || !(req.network in networks)) {
    throw new Error(`Unknown or invalid network: \`${req['network']}\`. Known networks: ${Object.keys(networkConfigs).join(',')}`);
  }

  // TODO: More validations
  return req as TrxRequest;
}

const fastify = Fastify({
  logger: true
});

fastify.post('/', async (req, reply) => {
  reply.type('application/json').code(200);

  let trxRequest = getTrxRequest(req.body as object);

  console.log({trxRequest});

  let network = networks[trxRequest.network];

  console.log({network});

  let encodedTrx = network.relayer.runTrxScript.populateTransaction(
    trxRequest.account,
    trxRequest.nonce,
    trxRequest.reqs,
    trxRequest.trxScript,
    trxRequest.expiry,
    trxRequest.v,
    trxRequest.r,
    trxRequest.s
  );

  console.log({encodedTrx});

  let submitSearchArgs = [
    network.relayer.address,
    encodedTrx.data,
    network.recipient,
    network.payToken,
    network.payTokenOracle,
    network.expectedWindfall,
    0
  ];

  console.log({submitSearchArgs});

  let submitSearch = gasSearcherInterface.encodeFunctionData('submitSearch', submitSearchArgs);

  console.log({submitSearch});

  let tx = await network.relayer.runQuark(searcherScript.object, submitSearch);

  return {
    tx
  };
});

async function start() {
  for (let [network, config] of Object.entries(networkConfigs)) {
    let provider = new StaticJsonRpcProvider(config.rpcUrl);
    let pk = process.env[`${network.toUpperCase()}_SEARCHER_PK`] ?? process.env['SEARCHER_PK'];
    if (!pk) {
      console.warn(`Cannot find ${network.toUpperCase()}_SEARCHER_PK or SEARCHER_PK, skipping network ${network}`);
      continue;
    }

    let wallet = new Wallet(pk)
    wallet.connect(provider);
    let signer: Signer = wallet;
    let relayer = new Contract(
      config.relayer,
      relayerAbi,
      signer
    );

    networks[network] = {
      relayer,
      provider,
      signer,
      recipient: await signer.getAddress(),
      payToken: config.payToken,
      payTokenOracle: config.payTokenOracle,
      expectedWindfall: config.expectedWindfall
    };
  }

  fastify.listen({ port: 3000 }, async (err, address) => {
    if (err) {
      fastify.log.error(err);
      process.exit(1);
    }

    console.error(`Searcher started on ${address}...`);
    // Server is now listening on ${address}
  });
}

start();
