import { describe, expect, test, beforeEach } from '@jest/globals';
import { Address, Uint256, Value } from '../src/Value';
import { Action, pipe, pop, __resetVarIndex } from '../src/Action';
import { pipeline } from '../src/Pipeline';
import { prepare } from '../src/Command';
import { add, sub } from './__Builtins';
import * as solc from 'solc';

describe('Building commands', () => {
  beforeEach(() => {
    __resetVarIndex();
  });

  test('Adds 3 and 4, minus 2', async () => {
    let command = await prepare(pipeline([
      pop(pipe(add(new Uint256(3), new Uint256(4)), (sum) => sub(sum, new Uint256(2))))
    ]), solc.compile);

    expect(command.yul).toEqual(`
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
}`);

    expect(command.bytecode).toEqual(`0x30303050505000`);

    expect(command.description).toEqual(`Pipeline:
  * Add 0x3 and 0x4 |> Subtract 0x2 from __v__0`);
  });
});
