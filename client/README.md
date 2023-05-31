
## Quark Client

The Quark client is a JavaScript library to quicky and easily build and invoke actions from Quark wallets. The goal of this library is to cover a large subset of actions one might want to take when using a Quark wallet, from simply wrapping Ethers transactions, to building compositions of built-in DeFi functions, to even running Solidity code.

## Getting Started

Start by installing this library:

```sh
npm install --save @compound-finance/quark

# yarn add @compound-finance/quark
```

Many commands will require a Web3 Provider, e.g. from Ethers. We will automatically detect the network and find the correct Quark Relayer. You can use this library to communicate with the Quark Relayer contract, e.g. to get your Quark wallet address:

```js
import * as Quark from '@compound-finance/quark';

// Get the relayer (an Ethers contract)
let relayer = await Quark.getRelayer(provider);

// Note: Relayer function names end in nonce numbers to help differentiate function calls from transaction scripts

// quarkAddress25(address) returns your Quark wallet address
console.log(await relayer.quarkAddress25('0x...'))
```

You can also pass options when getting the relayer, which makes this synchronous e.g.

```js
import * as Quark from '@compound-finance/quark';

// Get the relayer version 1 on arbitrum (note: only version 1 exists)
let relayer = Quark.Relayer(provider, 'arbitrum', 1);
```

## Examples

### Running Ethers function

While an Ethereum transaction is usually just data sent to a smart contract, Quark transactions are _transaction scripts_, that is: they run EVM code. This allows Quark scripts to be extremely powerful, but sometimes you want to just do the standard thing (send a simple function call to an existing smart contract). Quark lets you easily do that by wrapping the Ethers call in a simple transaction script:

```js
import * as Quark from '@compound-finance/quark';

let usdc = new ethers.Contract("0x...", [
  "function balanceOf(address owner) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
  "function transfer(address to, uint amount) returns (bool)",
], provider);

let command = await Quark.wrap(
  usdc.populateTransaction.approve(...));

console.log(`Command: ${command.description}`);
console.log(`Command YUL: ${command.yul}`);
console.log(`Command Bytecode: ${command.bytecode}`);

let tx = await Quark.exec(provider, command);
```

If you have raw data, you can easily send that, as well, or pass in a custom relayer, e.g.:

```js
import * as Quark from '@compound-finance/quark';

let command = await Quark.wrap(
  { to: '0x...', data: '0x...' });

console.log(`Command: ${command.description}`);
console.log(`Command YUL: ${command.yul}`);
console.log(`Command Bytecode: ${command.bytecode}`);

let tx = await Quark.exec(relayer, command);
```

### Pipelines and Built-ins

Quark becomes more interesting when you start to pipeline actions which will run atomically. While there's no limit to what Quark scripts can do, this library provides a simple way to pipeline actions, including passing data from one step in the pipeline to the next. Pipeline steps can be wrapped Ethers calls, or native Quark "built-ins" that provide more fine-grained access to DeFi functions.

For example, here's a simple pipeline to approve and supply using native built-ins. Notice that the approval amount and the supply amount are based on reading the exact Erc20 balance of the token.

```js
import * as Quark from '@compound-finance/quark';
import * as Erc20 from '@compound-finance/quark/builtins/erc20/arbitrum';
import * as cUSDCv3 from '@compound-finance/quark/builtins/comet/arbitrum';

let action = Quark.pipeline([
  Erc20.approve(cUSDCv3.underlying, cUSDCv3.address, Erc20.balanceOf(cUSDCv3.underlying, cUSDCv3.address)),
  cUSDCv3.supply(cUSDCv3.underlying, Erc20.balanceOf(cUSDCv3.underlying, cUSDCv3.address)),
]);

let command = await Quark.prepare(action);

console.log(`Command: ${command.description}`);
console.log(`Command YUL: ${command.yul}`);
console.log(`Command Bytecode: ${command.bytecode}`);

let tx = await Quark.exec(provider, command);
```

Note: you can also pipe using the `pipe` command explicitly to prevent double-reading the balance, e.g.:

```js
import * as Quark from '@compound-finance/quark';
import * as Erc20 from '@compound-finance/quark/builtins/erc20/arbitrum';
import * as cUSDCv3 from '@compound-finance/quark/builtins/comet/arbitrum';

let action = Quark.pipeline([
  Quark.pipe(Erc20.balanceOf(cUSDCv3.underlying, cUSDCv3.address), (bal) => {
    [
      Erc20.approve(cUSDCv3.underlying, cUSDCv3.address, bal),
      cUSDCv3.supply(cUSDCv3.underlying, bal),
    ]
  }
]);

let command = await Quark.prepare(action);

console.log(`Command: ${command.description}`);
console.log(`Command YUL: ${command.yul}`);
console.log(`Command Bytecode: ${command.bytecode}`);

let tx = await Quark.exec(provider, command);
```

You can also perform more complex actions, like combining Uniswap and Compound, e.g.

```js
import * as Quark from '@compound-finance/quark';
import * as Erc20 from '@compound-finance/quark/builtins/erc20/arbitrum';
import * as cUSDCv3 from '@compound-finance/quark/builtins/comet/arbitrum';
import * as Uniswap from '@compound-finance/quark/builtins/uniswap/arbitrum';

let action = Quark.pipeline([
  [
    Quark.pipe(Uniswap.singleSwap(cUSDCv3.underlying, Erc20.tokens.uni), (swapAmount) => [
      Erc20.approve(Erc20.tokens.uni, cUSDCv3.address, swapAmount)
      cUSDCv3.supply(swapAmount, cUSDCv3.underlying),
    ]),
  ]
]);
```

You can also wrap Ethers calls as a pipeline action via `invoke`. Note: you cannot easily pipe values from Ethers calls to other Ethers calls. Thus, you should prefer to use builtins where possible as they compose better.

```js
import * as Quark from '@compound-finance/quark';
import { invoke, readUint256 } from '@compound-finance/quark';
import * as cUSDCv3 from '@compound-finance/quark/builtins/comet/arbitrum';

let usdc = new ethers.Contract("0x...", [
  "function balanceOf(address owner) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
  "function transfer(address to, uint amount) returns (bool)",
], provider);

let comet = new ethers.Contract("0x...", [
  "function supply(address asset, uint256 amount)"
], provider);

let action = pipeline([
  invoke(await usdc.populateTransaction.approve(cUSDCv3.underlying, cUSDCv3.address, Quark.UINT256_MAX)),
  pipe(readUint256(usdc.balanceOf(cUSDCv3.underlying, cUSDCv3.address)), (bal) => [ // Read from Ethers call
    cUSDCv3.supply(cUSDCv3.underlying, bal) // Can pipe only to built-ins, not to Ethers calls
  ])
]);
```

### Solidity

** Solidity Support is Experimental

There is also experimental support for running Solidity code directly as a Quark command.

```js
import * as Quark from '@compound-finance/quark';

let command = await Quark.buildSol(`
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract Fun {
  event FunTimes(uint256);

  function hello() external {
    emit FunTimes(55);
  }
}
`);

console.log(`Command: ${command.description}`);
console.log(`Command YUL: ${command.yul}`);
console.log(`Command Bytecode: ${command.bytecode}`);

let tx = await Quark.exec(provider, command);
```

There are a lot of potential limitations in these scripts as we have less control over the generated code. It's recommended you inspect the Yul code directly to make sure it does what you would expect.

### Yul

You can also build a command directly from Yul.

```js
import * as Quark from '@compound-finance/quark';

let command = await Quark.buildYul(`
object "Ping" {
  code {
    // Store a value (55) in memory
    mstore(0x80, 55)

    // ABI topic for \`Ping(uint256)\`
    let topic := 0x48257dc961b6f792c2b78a080dacfed693b660960a702de21cee364e20270e2f

    // emit Ping(55)
    log1(0x80, 0x20, topic)

    return(0, 0)
  }
}
`);

console.log(`Command: ${command.description}`);
console.log(`Command YUL: ${command.yul}`);
console.log(`Command Bytecode: ${command.bytecode}`);

let tx = await Quark.exec(provider, command);
```

## Future Considerations

We could probably improve the ability to pipe data into Ethers invocations, but that is starting to get a little dicey. Leaving it as a note for now to address later.

We should make Solc/Yul compilation (optionally?) outside of the main thread.

## License

Copyright Geoffrey Hayes, Compound Labs, Inc. 2023. All rights reserved.

This software is provided "as-is" with no warranty whatsoever. By using this software, you agree that you shall arise no claim against the author or their representatives from any usage of this software.
