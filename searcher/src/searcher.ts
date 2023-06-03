

// TODO: Track fee token balances?

interface Context {
  priorityFee: number,
  volatility: number,
  baseTokenPrice: number,
  accountNonce: number,
  accountBaseToken: number,
  tokenBalances: { [feeToken: string]: bigint }
}

interface TrxScript {

}

interface Candidate {
  trxScript: TrxScript,
  feeToken: string,
  feeAmount: bigint,
  accountTokenBalance: bigint,
  estimatedGas: bigint,
  // TODO: Can add reqs and other goodies
}

type Response
  = { submitted: true, tx: TransactionResponse }
  | { submitted: false, rejection: string }

function buildContext(): Promise<Context> {

}

function buildTrxScript(bytes: string): TrxScript {

}

async function buildCandidate(trxScript: TrxScript): Promise<Candidate> {

}

function decideCandidate(ctx: Context, candidate: Candidate): null | string {

}

async function executeCandidate(candidate: Candidate): Promise<[Context, TransactionResponse]> {

}

async function receiveTrxScript(trxScript: string, ctx: Context): Promise<Response> {

} 

// TODO: Set-up a server or ways to receive trx scripts
// TODO: Ad