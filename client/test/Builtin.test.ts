import {describe, expect, test} from '@jest/globals';
import { Action, Address, Uint256, Value, yul, callSig, pipe, pipeline, prepare, pop } from '../src/Builtin';

export function add(x: Value<Uint256>, y: Value<Uint256>): Action<Uint256> {
  return {
    preamble: [
      yul`
        function _add(x, y) -> r {
          r := add(x, y)
        }
      `],
    statements: [
      `_add(${x.get()}, ${y.get()})`
    ],
    description: `Add ${x.get()} and ${y.get()}`,
    _: undefined,
  }
}

export function sub(x: Value<Uint256>, y: Value<Uint256>): Action<Uint256> {
  return {
    preamble: [
      yul`
        function _sub(x, y) -> r {
          r := sub(x, y)
        }
      `],
    statements: [
      `_sub(${x.get()}, ${y.get()})`
    ],
    description: `Subtract ${y.get()} from ${x.get()}`,
    _: undefined,
  }
}

describe('Pipelining actions', () => {
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
});

describe('Building commands', () => {
  test('Adds 3 and 4, minus 2', () => {
    let res = prepare(pipeline([
      pop(pipe(add(new Uint256(3), new Uint256(4)), (sum) => sub(sum, new Uint256(2))))
    ]));

    expect(res.yul).toEqual(`
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

    expect(res.bytecode).toEqual(`0x30303050505000`);

    expect(res.description).toEqual(`Pipeline:
  * Add 0x3 and 0x4 |> Subtract 0x2 from __v__0`);
  });
});
