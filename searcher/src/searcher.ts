import Fastify from 'fastify'
import { Contract } from '@ethersproject/contracts';
import { Interface } from '@ethersproject/abi';
import { StaticJsonRpcProvider } from '@ethersproject/providers';
import { Provider } from '@ethersproject/abstract-provider';
import { Signer } from '@ethersproject/abstract-signer';
import { Wallet } from '@ethersproject/wallet';
import { abi as relayerAbi } from '../../out/Relayer.sol/Relayer.json';
import { bytecode as searcherScript } from '../../out/GasSearcher.yul/Searcher.json'
import { Networks, NetworkConfig, getNetworks } from './network';
import { TrxRequest, getTrxRequest } from './trxRequest';

let networks: Networks = {};

const gasSearcherInterface = new Interface([
  "function submitSearch(address relayer, bytes calldata relayerCalldata, address recipient, address payToken, address payTokenOracle, uint256 expectedWindfall, uint256 gasPrice) external",
]);

const fastify = Fastify({
  logger: true
});

fastify.post('/', async (req, reply) => {
  reply.type('application/json').code(200);

  let trxRequest = getTrxRequest(networks, req.body as object);

  console.log({trxRequest});

  let network = networks[trxRequest.network];

  console.log({network});

  let encodedTrx = await network.relayer.populateTransaction.runTrxScript(
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
  let pk = process.env['SEARCHER_PK'];
  if (!pk) {
    throw new Error(`Must set SEARCHER_PK`);
  }

  networks = await getNetworks(pk);

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
