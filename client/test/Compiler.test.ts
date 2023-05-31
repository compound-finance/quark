import { describe, expect, test, beforeEach } from '@jest/globals';
import { Address, Uint256, Value } from '../src/Value';
import { Action, pipe, pop, __resetVarIndex } from '../src/Action';
import { pipeline } from '../src/Pipeline';
import { Command } from '../src/Command';
import { buildSol, buildYul } from '../src/Compiler';

describe('Compiling Yul', () => {
  beforeEach(() => {
    __resetVarIndex();
  });

  test('Builds proper Yul command', async () => {
    let yul = `
object "QuarkCommand" {
  code {
    verbatim_0i_0o(hex"303030505050")

    function _add(x, y) -> r {
      r := add(x, y)
    }

    function _sub(x, y) -> r {
      r := sub(x, y)
    }

    let __v__0 := _add(0x3, 0x4)

    pop(_sub(__v__0, 0x2))
  }
}`;

    let command = await buildYul(yul);

    expect(command.yul).toEqual(yul);
    expect(command.bytecode).toEqual(`0x30303050505000`);

    expect(command.description).toEqual(`Native Yul code`);
  });
});

describe('Compiling Solidity', () => {
  beforeEach(() => {
    __resetVarIndex();
  });

  test('Builds proper Sol command', async () => {
    let sol = `
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract Fun {
  event FunTimes(uint256);

  function hello() external {
    emit FunTimes(55);
  }
}`;

    let command = await buildSol(sol, 'hello');

    expect(command.yul).toMatch(/303030505050/);
    expect(command.bytecode).toEqual(`0x30303050505060806040527fa1591fde914eeec9b1f4af5ae4aa02e5df4a18be175afa9203f1307f5053151a602060405160378152a100fea26469706673582212200766e0e02530477512d53081c023b2e7f07cc2783a4fd22fc782740416f14d0164736f6c63430008140033`);
    expect(command.description).toEqual(`Native Yul code`);
  });
});
