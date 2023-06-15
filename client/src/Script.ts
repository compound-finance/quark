import { BigNumber } from '@ethersproject/bignumber';
import { AbiCoder, Interface } from '@ethersproject/abi';
import { hexDataSlice, hexlify } from '@ethersproject/bytes';
import { abi as flashMulticallAbi, deployedBytecode as flashMulticallBytecode } from '../../out/FlashMulticall.sol/FlashMulticall.json'
import { abi as multicallAbi, deployedBytecode as multicallBytecode } from '../../out/Multicall.sol/Multicall.json'
import { abi as searcherAbi, deployedBytecode as searcherBytecode } from '../../out/Searcher.sol/Searcher.json'
import { abi as ethcallAbi, deployedBytecode as ethcallBytecode } from '../../out/Ethcall.sol/Ethcall.json'
import { Contract } from '@ethersproject/contracts';
import { Provider, TransactionRequest } from '@ethersproject/abstract-provider';
import { Signer, TypedDataSigner } from '@ethersproject/abstract-signer';
import { getRelayer, getRelayerBySigner } from './Relayer';

let multicallInterface = new Interface(multicallAbi);
let ethcallInterface = new Interface(ethcallAbi);

let quarkScriptInterface = new Interface([
  "function _exec(bytes calldata data) external returns (bytes memory)"
]);

export type ContractCall = [Contract, string, any[]] | [Contract, string, any[], number | BigInt];
export type TransactionRequestOrPromise = TransactionRequest | Promise<TransactionRequest>;

export interface TrxScriptCall {
    trxScript: string,
    trxCalldata: string
}

export type TrxScript = TrxScriptCall & {
  account: string,
  nonce: number,
  reqs: number[],
  expiry: number
}

export type SignedTrxScript = TrxScript & {
  v: string,
  r: string,
  s: string
};

export type Call
  = ContractCall
  | TransactionRequestOrPromise;

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

function encodeTuple(args: string[], values: any[]): string {
  return new AbiCoder().encode(
    [`tuple(${args.join(',')})`],
    [values]
  );
}

async function encodeCall(call: Call): Promise<[string, string, BigInt]> {
  let txReq: TransactionRequest;

  if (Array.isArray(call)) {
    let [contract, method, args, value] = call;
    if (!(method in contract.populateTransaction)) {
      throw new Error(`${contract.name} does not have method ${method}`);
    }
    txReq = await contract.populateTransaction[method](...args, { value });
  } else {
    txReq = await call;
  }
  console.log("txReq", txReq);

  return [txReq.to!, hexlify(txReq.data!), txReq.value ? BigNumber.from(txReq.value).toBigInt() : 0n];
}

export async function getRelayerFrom(providerOrRelayer: Provider | Contract): Promise<Contract> {
  let relayer: Contract;
  if (providerOrRelayer instanceof Contract) {
    relayer = providerOrRelayer;
  } else {
    relayer = await getRelayer(providerOrRelayer);
  }
  return relayer;
}

export async function runQuarkScript(providerOrRelayer: Provider | Contract, script: string, calldata: string, sendArgs?: object): Promise<any> {
  let relayer = await getRelayerFrom(providerOrRelayer);
  console.log("relayer", relayer, script, calldata, sendArgs);
  return relayer['runQuarkScript(bytes,bytes)'](script, calldata, sendArgs ?? {});
}

export async function multicallTrxScriptCall(calls: Call[], wrap = false): Promise<TrxScriptCall> {
  console.log("calls", calls);
  if (calls.length !== 1) {
    // Multicall
    if (calls.length === 0) {
      throw new Error('Empty call list given');
    }
    console.log("calls", calls);
    let callsEncoded = await Promise.all(calls.map(encodeCall));
    let inAddresses = callsEncoded.map((c) => c[0]);
    let inCalldatas = callsEncoded.map((c) => c[1]);
    let inCallvalues = callsEncoded.map((c) => c[2]);

    let multicallInput = encodeTuple(["address[]", "bytes[]", "uint256[]"], [inAddresses, inCalldatas, inCallvalues]);

    let trxCalldata = multicallInput;
    if (wrap) {
      trxCalldata = quarkScriptInterface.encodeFunctionData('_exec', [multicallInput])
    }

    return {
      trxScript: multicallBytecode.object,
      trxCalldata
    };
  } else {
    // Single call
    let [call] = calls;

    console.log("single", call);
    let encoded = await encodeCall(call);
    console.log("encoded", encoded);

    let ethcallInput = encodeTuple(["address", "bytes", "uint256"], encoded);
    console.log("ethCallInput", ethcallInput);

    let trxCalldata = ethcallInput;
    if (wrap) {
      trxCalldata = quarkScriptInterface.encodeFunctionData('_exec', [ethcallInput])
    }

    return {
      trxScript: ethcallBytecode.object,
      trxCalldata
    };
  }
}

export async function multicall(providerOrRelayer: Provider | Contract, calls: Call[], sendArgs?: object): Promise<any> {
  let { trxScript, trxCalldata } = await multicallTrxScriptCall(calls);
  return runQuarkScript(providerOrRelayer, trxScript, trxCalldata, sendArgs);
}

export async function multicallSign(signer: Signer, chainId: number, calls: Call[], nonce: number, reqs: number[], expiry: number): Promise<SignedTrxScript> {
  let { trxScript, trxCalldata } = await multicallTrxScriptCall(calls, true);
  return signTrxScript(signer, chainId, await signer.getAddress(), nonce, reqs, trxScript, trxCalldata, expiry);
}

export async function flashMulticall(providerOrRelayer: Provider | Contract, pool: string, amount0: bigint, amount1: bigint, calls: Call[], sendArgs?: object): Promise<any> {
  console.log("calls", calls);
  let callsEncoded = await Promise.all(calls.map(encodeCall));
  let inAddresses = callsEncoded.map((c) => c[0]);
  let inCalldatas = callsEncoded.map((c) => c[1]);

  let flashMulticallInput = encodeTuple(["address", "uint256", "uint256", "address[]", "bytes[]"], [pool, amount0, amount1, inAddresses, inCalldatas]);

  return runQuarkScript(providerOrRelayer, flashMulticallBytecode.object, flashMulticallInput, sendArgs);
}

export async function submitSearch(providerOrRelayer: Provider | Contract, trxScript: SignedTrxScript, beneficiary: string, baseFee: BigInt, sendArgs?: object): Promise<any> {
  console.log("trx script", trxScript);
  console.log("beneficiary", beneficiary);
  console.log("baseFee", baseFee);

  let input = encodeTuple([
    "address",
    "uint32",
    "uint32[]",
    "bytes",
    "bytes",
    "uint256",
    "uint8",
    "bytes32",
    "bytes32",
    "address",
    "uint256",
  ],
  [
    trxScript.account,
    trxScript.nonce,
    trxScript.reqs,
    trxScript.trxScript,
    trxScript.trxCalldata,
    trxScript.expiry,
    trxScript.v,
    trxScript.r,
    trxScript.s,
    beneficiary,
    baseFee,
  ]);

  return runQuarkScript(providerOrRelayer, searcherBytecode.object, input, sendArgs);
}

export async function callTrxScript(providerOrRelayer: Provider | Contract, trxScript: SignedTrxScript, callArgs?: object): Promise<any> {
  let relayer = await getRelayerFrom(providerOrRelayer);
  
  return await relayer.callStatic.runTrxScript(
    trxScript.account,
    trxScript.nonce,
    trxScript.reqs,
    trxScript.trxScript,
    trxScript.trxCalldata,
    trxScript.expiry,
    trxScript.v,
    trxScript.r,
    trxScript.s,
    callArgs ?? {}
  )
}

export async function sendTrxScript(providerOrRelayer: Provider | Contract, trxScript: SignedTrxScript, sendArgs?: object): Promise<any> {
  let relayer = await getRelayerFrom(providerOrRelayer);

  return await relayer.runTrxScript(
    trxScript.account,
    trxScript.nonce,
    trxScript.reqs,
    trxScript.trxScript,
    trxScript.trxCalldata,
    trxScript.expiry,
    trxScript.v,
    trxScript.r,
    trxScript.s,
    sendArgs
  );
}

export async function signTrxScript(
  signer: Signer,
  chainId: number,
  account: string,
  nonce: number,
  reqs: number[],
  trxScript: string,
  trxCalldata: string,
  expiry: number): Promise<SignedTrxScript> {
  let relayer = getRelayerBySigner(signer, chainId);

  // All properties on a domain are optional
  const domain = {
    name: 'Quark',
    version: '0',
    chainId,
    verifyingContract: relayer.address
  };

  // The data to sign
  const trxScriptStruct = {
    account,
    nonce,
    reqs,
    trxScript,
    trxCalldata,
    expiry,
  }

  let signature = hexlify(await (signer as unknown as TypedDataSigner)._signTypedData(domain, trxScriptTypes, trxScriptStruct));
  let r = hexDataSlice(signature, 0, 32);
  let s = hexDataSlice(signature, 32, 64);
  let v = hexDataSlice(signature, 64, 65);

  return {
    ...trxScriptStruct,
    v,
    r,
    s,
  };
}
