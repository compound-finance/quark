
## Quark JavaScript Client


## Examples

Simple pipeline:

```js
import * as QuarkQL from '@compound-finance/quark';
import * as Erc20 from '@compound-finance/quark/builtins/erc20/arbitrum';
import * as cUSDCv3 from '@compound-finance/quark/builtins/comet/arbitrum';

let action = QuarkQL.pipeline([
  Erc20.approve(cUSDCv3.underlying, cUSDCv3.address, QuarkQL.UINT256_MAX),
  cUSDV3.supply(Erc20.balanceOf(cUSDCv3.underlying), cUSDCv3.underlying),
]);

let command = await QuarkQL.prepare(action);

console.log(`Command: ${command.description}`);
console.log(`Command YUL: ${command.yul}`);
console.log(`Command Bytecode: ${command.bytecode}`);

let tx = await QuarkQL.exec(provider, command);
```

Pipeline with variables:

```js
import * as QuarkQL from '@compound-finance/quark';
import * as Erc20 from '@compound-finance/quark/builtins/erc20/arbitrum';
import * as cUSDCv3 from '@compound-finance/quark/builtins/comet/arbitrum';
import * as Uniswap from '@compound-finance/quark/builtins/uniswap/arbitrum';

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

let tx = await QuarkQL.exec(provider, command);
```
