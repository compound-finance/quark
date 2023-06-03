import { Contract } from '@ethersproject/contracts';
import { StaticJsonRpcProvider } from '@ethersproject/providers';
import { abi } from '../../out/Relayer.sol/Relayer.json';


let usdc = new Contract(
  "0x112233445566778899aabbccddeeff0011223344",
  [abi],
  new StaticJsonRpcProvider(''));

// TODO: Track fee token balances?

// TODO: ABC
interface Context {
  baseFee: number,
  prices: { [token]: number }, // in base token
  relayers: {
    []
  }
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

function buildContext(): Promise<Context> {
  return {
    baseFee: 
  }
}

async function receiveTrxScript(trxScript: string, ctx: Context): Promise<Response> {

} 

// TODO: Set-up a server or ways to receive trx scripts
// TODO: Ad