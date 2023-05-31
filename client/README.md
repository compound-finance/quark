
## Quark JavaScript Client


## Examples

Simple pipeline:

```js
import { QuarkQL, Erc20 } from '@compound-finance/quark';
import { cUSDCv3 } from '@compound-finance/quark-builtins';

function* myFn() {
  let x = yield Erc20.approve(cUSDCv3.underlying, cUSDCv3.address, QuarkQL.UINT256_MAX); // Value<[Address, Uint2256]>
  let y = yield Erc20.approve(cUSDCv3.underlying, cUSDCv3.address, QuarkQL.UINT256_MAX); // Value<[Address, Uint2256]>
  yield cUSDV3.supply(Erc20.balanceOf(cUSDCv3.underlying), cUSDCv3.underlying, x, y);
  yield cUSDV3.borrowAll();
}

myHelper([
  Erc20.approve(cUSDCv3.underlying, cUSDCv3.address, QuarkQL.UINT256_MAX), // Value<[Address, Uint2256]>
  Erc20.approve(cUSDCv3.underlying, cUSDCv3.address, QuarkQL.UINT256_MAX), // Value<[Address, Uint2256]>
  cUSDV3.supply(Erc20.balanceOf(cUSDCv3.underlying), cUSDCv3.underlying),
  cUSDV3.borrowAll(),
  pipe(<const>[ a(), b() ], ([ a, b ]) => c(a, b))
]);

  // let ctx = {}; while (ctx = yield execute(ctx), !!ctx.done) {}
let action = QuarkQL.build(myFn);

console.log(`Action: ${action.description}`);
console.log(`Action YUL: ${action.yul}`);
console.log(`Action Bytecode: ${action.bytecode}`);

let tx = QuarkQL.exec(provider, action);
```

Pipeline with variables:

```js
import { QuarkQL } from '@compound-finance/quark';
import { Erc20, cUSDCv3, Uniswap } from '@compound-finance/quark-builtins/arbitrum';

let action = QuarkQL.pipeline([
  [
    pipe(Uniswap.singleSwap(cUSDCv3.underlying, Erc20.tokens.uni), (swapAmount) => [
      Erc20.approve(Erc20.tokens.uni, cUSDCv3.address, swapAmount)
      cUSDV3.supply(Erc20.balanceOf(cUSDCv3.underlying), cUSDCv3.underlying),
    ]),
  ]
]);

let command = await QuarkQL.prepare(action);

console.log(`Command: ${command.description}`);
console.log(`Command YUL: ${command.yul}`);
console.log(`Command Bytecode: ${command.bytecode}`);

let result = await QuarkQL.exec(provider, command);
```
