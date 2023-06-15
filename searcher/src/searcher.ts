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

import type { SignedTrxScript } from '../../client/src/Script';
import * as Quark from '../../client/src/Quark';

let networks: Networks = {};

const fastify = Fastify({
  logger: true
});

fastify.post('/', async (req, reply) => {
  reply.type('application/json').code(200);

  let trxRequest = getTrxRequest(networks, req.body as object);

  console.log({trxRequest});

  let network = networks[trxRequest.network];

  console.log({network});

  let tx = await Quark.Script.submitSearch(
    network.signer as any,
    trxRequest,
    network.beneficiary,
    network.baseFee
  );

  console.log({tx});

  // TODO: Ensure this fails if it doesn't work

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
