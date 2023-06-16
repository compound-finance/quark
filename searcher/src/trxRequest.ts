import type { Networks } from './network';
import type { SignedTrxScript } from '../../client/src/Script';

export type TrxRequest = SignedTrxScript & {
  network: string
};

export function getTrxRequest(networks: Networks, req: object): TrxRequest {
  if (!('network' in req)) {
    throw new Error(`Missing required key \`network\``);
  }

  if (typeof(req.network) === 'number') {
    let n = Object.entries(networks).find(([_, config]) => config.chainId === req.network);
    if (n) {
      req.network = n[0];
    }
  }

  console.log("network", req.network);

  if (typeof(req.network) !== 'string' || !(req.network in networks)) {
    throw new Error(`Unknown or invalid network: \`${req['network']}\`. Known networks: ${Object.keys(networks).join(',')}`);
  }

  // TODO: More validations
  return req as TrxRequest;
}
