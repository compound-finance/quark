import Fastify from 'fastify'
import { Contract } from '@ethersproject/contracts';
import { Interface } from '@ethersproject/abi';
import { StaticJsonRpcProvider } from '@ethersproject/providers';
import { Provider } from '@ethersproject/abstract-provider';
import { Signer } from '@ethersproject/abstract-signer';
import { Wallet } from '@ethersproject/wallet';
import { abi as relayerAbi } from '../../out/Relayer.sol/Relayer.json';
import { bytecode as searcherScript } from '../../out/GasSearcher.yul/Searcher.json'

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

const gasSearcherInterface = new Interface([
  "function submitSearch(address relayer, bytes calldata relayerCalldata, address recipient, address payToken, address payTokenOracle, uint256 expectedWindfall, uint256 gasPrice) external",
]);

export interface TrxRequest {
  network: string,
  account: string,
  nonce: number,
  reqs: number[],
  trxScript: string,
  expiry: number,
  v: string,
  r: string,
  s: string
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

  let encodedTrx = await network.relayer.populateTransaction.runTrxScript(
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

  let tx = await network.relayer['runQuark(bytes,bytes)'](searcherScript.object, submitSearch);

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

    let wallet = new Wallet(pk).connect(provider);
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
