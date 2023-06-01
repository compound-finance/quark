import { describe, expect, test, beforeEach } from '@jest/globals';
import { Address, Uint256, Value } from '../src/Value';
import { Action, pipe, pop, __resetVarIndex } from '../src/Action';
import { pipeline } from '../src/Pipeline';
import { prepare } from '../src/Command';
import { Contract } from '@ethersproject/contracts';
import { StaticJsonRpcProvider } from '@ethersproject/providers';
import { invoke, readUint256 } from '../src/Invocation';
import { add } from './__Builtins';
import * as solc from 'solc';

let from = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
let to = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

let usdc = new Contract("0x112233445566778899aabbccddeeff0011223344", [
  "function balanceOf(address owner) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
  "function transfer(address to, uint amount) returns (bool)",
], new StaticJsonRpcProvider(''));

describe('Invocations', () => {
  beforeEach(() => {
    __resetVarIndex();
  });

  test('Erc20 Transfer', async () => {
    let action = pipeline([
      invoke(await usdc.populateTransaction.transfer(to, 100e8))
    ]);

    let command = await prepare(action, solc.compile);

    console.log(`Command: ${command.description}`);
    console.log(`Command YUL: ${command.yul}`);
    console.log(`Command Bytecode: ${command.bytecode}`);
  });

  test('Erc20 Read Balance', async () => {
    let action = pipeline([
      pop(add(new Uint256(1), readUint256(await usdc.populateTransaction.balanceOf(to))))
    ]);

    let command = await prepare(action, solc.compile);

    console.log(`Command: ${command.description}`);
    console.log(`Command YUL: ${command.yul}`);
    console.log(`Command Bytecode: ${command.bytecode}`);
  });
});
