import { describe, expect, test, beforeEach } from '@jest/globals';
import { Address, Uint256, Value } from '../src/Value';
import { Action, pipe, pop, __resetVarIndex } from '../src/Action';
import { pipeline } from '../src/Pipeline';
import { add, sub } from './__Builtins';

describe('Pipelining actions', () => {
  beforeEach(() => {
    __resetVarIndex();
  });

  test('Adds 1 and 2', () => {
    expect(
      pipeline([
        pop(add(new Uint256(1), new Uint256(2)))
      ])
    ).toEqual(
      {
        _: undefined,
        description: `Pipeline:
  * Add 0x1 and 0x2`,
        preamble: [`function _add(x, y) -> r {
  r := add(x, y)
}`],
        statements: ["pop(_add(0x1, 0x2))"]
      });
  });

  test('Adds 3 and 4, minus 2', () => {
    expect(
      pipeline([
        pipe(add(new Uint256(3), new Uint256(4)), (sum) => pop(sub(sum, new Uint256(2))))
      ])
    ).toEqual(
      {
        _: undefined,
        description: `Pipeline:
  * Add 0x3 and 0x4 |> Subtract 0x2 from __v__0`,
        preamble: [
`function _add(x, y) -> r {
  r := add(x, y)
}`,
`function _sub(x, y) -> r {
  r := sub(x, y)
}`],
        statements: [
          "let __v__0 := _add(0x3, 0x4)",
          "pop(_sub(__v__0, 0x2))"
        ]
      });
  });

  test('Inline: Adds 3 and 4, minus 2', () => {
    expect(
      pipeline([
        pop(sub(add(new Uint256(3), new Uint256(4)), new Uint256(2)))
      ])
    ).toEqual(
      {
        _: undefined,
        description: `Pipeline:
  * Add 0x3 and 0x4 |> Subtract 0x2 from __v__0`,
        preamble: [
`function _add(x, y) -> r {
  r := add(x, y)
}`,
`function _sub(x, y) -> r {
  r := sub(x, y)
}`],
        statements: [
          "let __v__0 := _add(0x3, 0x4)",
          "pop(_sub(__v__0, 0x2))"
        ]
      });
  });
});
