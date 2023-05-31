import { Address, Uint256, Value } from '../src/Value';
import { Yul, yul } from '../src/Yul';
import { Action, Input, buildAction } from '../src/Action';

export function add(x: Input<Uint256>, y: Input<Uint256>): Action<Uint256> {
  return buildAction<[Uint256, Uint256], Uint256>(
    <const>[x, y],
    ([x, y]) => ({
      preamble: yul`
        function _add(x, y) -> r {
          r := add(x, y)
        }
      `,
      statements: yul`_add(${x.get()}, ${y.get()})`,
      description: `Add ${x.get()} and ${y.get()}`,
    })
  );
}

export function sub(x: Input<Uint256>, y: Input<Uint256>): Action<Uint256> {
  return buildAction<[Uint256, Uint256], Uint256>(
    <const>[x, y],
    ([x, y]) => ({
      preamble: yul`
        function _sub(x, y) -> r {
          r := sub(x, y)
        }
      `,
      statements: yul`_sub(${x.get()}, ${y.get()})`,
      description: `Subtract ${y.get()} from ${x.get()}`,
    })
  );
}
