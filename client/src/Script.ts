import { AbiCoder, Interface } from '@ethersproject/abi';
import { hexDataSlice, hexlify } from '@ethersproject/bytes';
import { abi as flashMulticallAbi, deployedBytecode as flashMulticallBytecode } from '../../out/FlashMulticall.sol/FlashMulticall.json'
import { abi as multicallAbi, deployedBytecode as multicallBytecode } from '../../out/Multicall.sol/Multicall.json'
import { abi as ethcallAbi, deployedBytecode as ethcallBytecode } from '../../out/Ethcall.sol/Ethcall.json'
import { Contract } from '@ethersproject/contracts';
import { Provider, TransactionRequest } from '@ethersproject/abstract-provider';
import { getRelayer } from './Relayer';

let multicallInterface = new Interface(multicallAbi);
let ethcallInterface = new Interface(ethcallAbi);

export type ContractCall = [Contract, string, any[]];
export type TrxRequest = TransactionRequest | Promise<TransactionRequest>;

export type Call
  = ContractCall
  | TrxRequest;

function encodeTuple(args: string[], values: any[]): string {
  return new AbiCoder().encode(
    [`tuple(${args.join(',')})`],
    [values]
  );
}

async function encodeCall(call: Call): Promise<[string, string]> {
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

export async function runQuarkScript(providerOrRelayer: Provider | Contract, script: string, calldata: string, sendArgs?: object): Promise<any> {
  let relayer: Contract;
  if (providerOrRelayer instanceof Contract) {
    relayer = providerOrRelayer;
  } else {
    relayer = await getRelayer(providerOrRelayer);
  }
  console.log("relayer", relayer, script, calldata, sendArgs);
  return relayer['runQuarkScript(bytes,bytes)'](script, calldata, sendArgs ?? {});
}

export async function multicall(providerOrRelayer: Provider | Contract, calls: Call[], sendArgs?: object): Promise<any> {
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

    let multicallInput = encodeTuple(["address[]", "bytes[]"], [inAddresses, inCalldatas]);

    return runQuarkScript(providerOrRelayer, multicallBytecode.object, multicallInput, sendArgs);
  } else {
    // Single call
    let [call] = calls;

    console.log("single", call);
    let encoded = await encodeCall(call);
    console.log("encoded", encoded);

    let ethcallInput = encodeTuple(["address", "bytes"], encoded);
    console.log("ethCallInput", ethcallInput);

    return runQuarkScript(providerOrRelayer, ethcallBytecode.object, ethcallInput, sendArgs);
  }
}

export async function flashMulticall(providerOrRelayer: Provider | Contract, pool: string, amount0: bigint, amount1: bigint, calls: Call[], sendArgs?: object): Promise<any> {
  console.log("calls", calls);
  let callsEncoded = await Promise.all(calls.map(encodeCall));
  let inAddresses = callsEncoded.map((c) => c[0]);
  let inCalldatas = callsEncoded.map((c) => c[1]);

  let flashMulticallInput = encodeTuple(["address", "uint256", "uint256", "address[]", "bytes[]"], [pool, amount0, amount1, inAddresses, inCalldatas]);

  return runQuarkScript(providerOrRelayer, flashMulticallBytecode.object, flashMulticallInput, sendArgs);
}
