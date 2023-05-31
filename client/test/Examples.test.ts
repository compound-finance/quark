import { describe, expect, test, beforeEach } from '@jest/globals';
import { Address, Uint256, Value } from '../src/Value';
import { Action, pipe, pop, __resetVarIndex } from '../src/Action';
import { pipeline } from '../src/Pipeline';
import { prepare } from '../src/Command';
import { cUSDCv3 } from '../src/builtins/comet/arbitrum';
import * as Erc20 from '../src/builtins/tokens/core';
import * as QuarkQL from '../src/QuarkQL';

describe('Example commands', () => {
  beforeEach(() => {
    __resetVarIndex();
  });

  test('Comet Supply [Arbitrum]', async () => {
    let action = pipeline([
      Erc20.approve(cUSDCv3.underlying, cUSDCv3.address, QuarkQL.UINT256_MAX),
      cUSDCv3.supply(cUSDCv3.underlying, Erc20.balanceOf(cUSDCv3.underlying, cUSDCv3.address)),
    ]);

    let command = await prepare(action);

    console.log(`Command: ${command.description}`);
    console.log(`Command YUL: ${command.yul}`);
    console.log(`Command Bytecode: ${command.bytecode}`);
  });
});
