import { AbiCoder, Interface } from '@ethersproject/abi';
import { hexDataSlice, hexlify } from '@ethersproject/bytes';
import { abi as multicallAbi, deployedBytecode as multicallBytecode } from '../../out/Multicall.sol/Multicall.json'
import { abi as ethcallAbi, deployedBytecode as ethcallBytecode } from '../../out/Ethcall.sol/Ethcall.json'
import { Contract } from '@ethersproject/contracts';
import { Provider, TransactionRequest } from '@ethersproject/abstract-provider';
import { getRelayer } from './Relayer';

let multicallInterface = new Interface(multicallAbi);
let ethcallInterface = new Interface(ethcallAbi);

export type ContractCall = [Contract, string, any[]];
export type TrxRequest = TransactionRequest | Promise<TransactionRequest>;

export type SingleCall
  = ContractCall
  | TrxRequest;

export type CallArgs
  = ContractCall
  | [TrxRequest]
  | [SingleCall[]];

function encodeTuple(args: string[], values: any[]): string {
  return '0x' + new AbiCoder().encode(
    [`tuple(${args.join(',')})`],
    [values]
  ).slice(66);
}

async function encodeCall(call: SingleCall): Promise<[string, string]> {
  let txReq: TransactionRequest;

  if (Array.isArray(call)) {
    let [contract, method, args] = call;
    if (!(method in contract.populateTransaction)) {
      throw new Error(`${contract.name} does not have method ${method}`);
    }
    txReq = await contract.populateTransaction[method](...args);
  } else {
    txReq = await call;
  }
  console.log("txReq", txReq);

  return [txReq.to!, hexlify(txReq.data!)];
}

export async function runQuarkScript(providerOrRelayer: Provider | Contract, script: string, calldata: string): Promise<any> {
  let relayer: Contract;
  if (providerOrRelayer instanceof Contract) {
    relayer = providerOrRelayer;
  } else {
    relayer = await getRelayer(providerOrRelayer);
  }
  console.log("relayer", relayer, script, calldata);
  return relayer['runQuarkScript(bytes,bytes)'](script, calldata);
}

export async function multicall(providerOrRelayer: Provider | Contract, ...callArgs: CallArgs): Promise<any> {
  console.log("callArgs", callArgs, callArgs.length, Array.isArray(callArgs[0]));
  if (callArgs.length > 0 && Array.isArray(callArgs[0]) && callArgs[0].length !== 1) {
    // Multicall
    let calls = callArgs[0] as SingleCall[];
    if (calls.length === 0) {
      throw new Error('Empty call list given');
    }
    console.log("calls", calls);
    let callsEncoded = await Promise.all(calls.map(encodeCall));
    let inAddresses = callsEncoded.map((c) => c[0]);
    let inCalldatas = callsEncoded.map((c) => c[1]);

    let multicallInput = encodeTuple(["address[]", "bytes[]"], [inAddresses, inCalldatas]);

    return runQuarkScript(providerOrRelayer, multicallBytecode.object, multicallInput);
  } else {
    // Single call
    let single: SingleCall;
    if (Array.isArray(callArgs[0]) && callArgs[0].length === 1) {
      single = callArgs[0][0];
    } else if (callArgs[0] instanceof Contract) {
      single = callArgs as ContractCall;
    } else {
      single = callArgs[0] as TrxRequest;
    }

    console.log("single", single);
    let encoded = await encodeCall(single);
    console.log("encoded", encoded);

    let ethcallInput = encodeTuple(["address", "bytes"], encoded);
    console.log("ethCallInput", ethcallInput);

    return runQuarkScript(providerOrRelayer, ethcallBytecode.object, ethcallInput);
  }
}
