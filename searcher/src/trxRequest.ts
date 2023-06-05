import type { Networks } from './network';

export interface TrxRequest {
  network: string,
  account: string,
  nonce: number,
  reqs: number[],
  trxScript: string,
  trxCalldata: string,
  expiry: number,
  v: string,
  r: string,
  s: string
}

export function getTrxRequest(networks: Networks, req: object): TrxRequest {
  if (!('network' in req)) {
    throw new Error(`Missing required key \`network\``);
  }

  if (typeof(req.network) !== 'string' || !(req.network in networks)) {
    throw new Error(`Unknown or invalid network: \`${req['network']}\`. Known networks: ${Object.keys(networks).join(',')}`);
  }

  // TODO: More validations
  return req as TrxRequest;
}
