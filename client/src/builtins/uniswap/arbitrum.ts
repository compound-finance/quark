import { Value, Bool, Address, Uint256 } from '../../Value';
import { Action, Input, buildAction } from '../../Action';
import { yul } from '../../Yul';
import { callSig } from '../../Util';

export function singleSwap(inAsset: Input<Address>, outAsset: Input<Address>, inAmount: Input<Uint256>): Action<Uint256> {
  return buildAction<[Address, Address, Uint256], Uint256>(
    [inAsset, outAsset, inAmount],
    ([inAsset, outAsset, inAmount]) => ({
      preamble: [
        yul`
          function __uniswap__singleSwap(inAsset, outAsset, inAmount) -> res {
            revert(0, 0) // TODO
          }
        `],
      statements: [
        `__uniswap__singleSwap(${inAsset.get()}, ${outAsset.get()}, ${inAmount.get()})`
      ],
      description: `Uniswap Swap [${inAsset.get()}->${outAsset.get()}]`,
    })
  );
}
