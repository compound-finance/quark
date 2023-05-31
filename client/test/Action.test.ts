import { describe, expect, test, beforeEach } from '@jest/globals';
import { Address, Uint256, Value } from '../src/Value';
import { Action, pipe, pop, __resetVarIndex } from '../src/Action';
import { add, sub } from './__Builtins';

describe('Building actions', () => {
  beforeEach(() => {
    __resetVarIndex();
  });

  test('Adds 1 and 2', () => {
    expect(
      pop(add(new Uint256(1), new Uint256(2)))
    ).toEqual(
      {
        _: undefined,
        description: `Add 0x1 and 0x2`,
        preamble: [`function _add(x, y) -> r {
  r := add(x, y)
}`],
        statements: ["pop(_add(0x1, 0x2))"]
      });
  });
});
