import { Address, Uint256, Value } from '../src/Value';
import { yul } from '../src/Yul';
import { Action } from '../src/Action';

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