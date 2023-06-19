
## Quark

Turn every Ethereum EOA into a smart contract wallet. Quark uses [metamorphic contracts](https://0age.medium.com/the-promise-and-the-peril-of-metamorphic-contracts-9eb8b8413c5e) to create a virtual account associated with your EOA which can send arbitrary logic with each transaction. Say you want to buy and sell two assets on Uniswap atomically: you can send that in a quark transaction without deploying a smart contract. You can then turn around and send another transaction from the same account that supplies atomically to two DeFi protocols. Quark brings the idea of "transaction scripts" to Ethereum and removes the need of using "smart contract wallets" to manage positions.

## How it works

Quark uses metamorphic contracts-- that is, contracts made using `CREATE2` that have dynamic code. Specifically, quark deploys a contract for each transaction you make and then forces it to `SELFDESTRUCT`, freeing it up for new logic for your next transaction.

Note, your transactions won't come from your EOA address directly-- but they will come from an address derived from your EOA. Thus you can think of each EOA having a second address (its quark address) that effectively becomes your new address. This should act like a normal Ethereum address from your perspective, though you won't be able to sign messages from it.

To send a Quark transaction, you simply send the EVM code that you want to run to the Quark Relayer contract. E.g.

```json
{ "to": "0xQuarkRelayer", "data": "{evm bytecode}" }
```

That code will run as a transaction script in your quark address, performing whatever operations you've specified (e.g. trading on Uniswap, etc). There is no trust being granted to Quark, and the Quark Relayer itself is not upgradable.

## Using Quark

There's nothing to do-- you can simply start sending Quark transactions today.

| Network       | Quark Relayer |
| ------------- | ------------- |
| Goerli        | [0xc4f0049a828cd0af222fdbe5adeda9aaf72b7f30](https://goerli.etherscan.io/address/0xc4f0049a828cd0af222fdbe5adeda9aaf72b7f30) |
| Optimism [Goerli] | [0x66ca95f4ed181c126acbd5aad21767b20d6ad7da](https://goerli-optimism.etherscan.io/address/0x66ca95f4ed181c126acbd5aad21767b20d6ad7da) |
| Arbitrum [Goerli] | [0xdde0bf030f2ffceae76817f2da0a14b1e9a87041](https://goerli.arbiscan.io/address/0xdde0bf030f2ffceae76817f2da0a14b1e9a87041) |
| Arbitrum [Mainnet] | [0x66ca95f4ed181c126acbd5aad21767b20d6ad7da](https://arbiscan.io/address/0x66ca95f4ed181c126acbd5aad21767b20d6ad7da) |

You can send scripts through a dApp, but they are simply data, so you can even send this via MetaMask. Try sending these transaction scripts on Goerli:

### Quark Scripts

The easiest way to use Quark is to through Quark Scripts.

```ts
import * as Quark from '@compound-finance/quark';

let tx = await Quark.Script.multicall(provider, [
  usdc.populateTransaction.transfer(100, '0x...')
]);
```

The [Multicall](#) Quark script wraps one or more Ethereum calls into a single transaction sent from your Quark address that run atomically. You can easily send these from a dApp like you're using today.

The following core scripts ship with Quark:

  * [Ethcall]() - Wraps a single Ethereum call [via [Quark.Script.multicall](#) with a single call]
  * [Multicall](#) - Wraps multiple Ethereum calls into a single script [via [Quark.Script.multicall](#)]
  * [FlashMulticall](#) - Performs a flash loan from Uniswap and then wraps a set of Ethereum calls [[Quark.Script.flashMulticall](#)]
  * [Searcher](#) - Account abstraction to submit a signed Quark transaction if and only if it nets the sender positive ether. [[Quark.Script.submitSearch](#)]

See the [Quark Client](#) for more details on the JavaScript client.

### Creating your own Scripts

You can make your own scripts to send from a Quark Wallet. For instance:

```js
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./QuarkScript.sol";

contract SayHello is QuarkScript {
  event Hello(string message);

  function run(string calldata message) external onlyRelayer {
    emit Hello(message);
  }
}
```

This script will simply emit a log message. Note: you do not need to derive from `QuarkScript`, but it will make it easier if you want to prevent other Ethereum contracts from calling into your script with the `onlyRelayer` modifier.

To run your script, make sure it's compiled and you have the `deployedBytecode` from the artifact, then run:


```js
import * as Quark from '@compound-finance/quark';
import { deployedBytecode as sayHelloCode } from '../out/SayHello.sol/SayHello.json';

let tx = await Quark.runQuarkScript(provider, sayHelloCode, "run(bytes calldata message)", ["world"]);
```

This will run your script as a transaction via Quark.

## Signed Transaction Scripts

You can also sign Quark transcription scripts, which can then be submitted by anyone on your behalf (e.g. from a gasser wallet you control or a searcher). For instance, to sign a mulitcall script:

```js
import * as Quark from '@compound-finance/quark';

let signedTrxScript = await multicallSign({
  signer,
  chainId,
  calls: [
    usdc.populateTransaction.transfer(100, '0x...')
  ],
  nonce: 0,
  reqs: [],
  expiry: Date.now() + 1000
});

let tx = await Quark.runTrxScript(provider, signedTrxScript);
```

### Searchers

You can easily run a searcher, which accepts signed transaction scripts and submits them to the blockchain if and only if you make a profit from the transaction. Specifically, the transaction script you submit must send you (`tx.origin` at least the gas cost in Ether of the transaction plus some base fee you charge). This is easily accomplished from Quark scripts as they can run any EVM code. The `Multicall` Quark Script has a special address which is replaced by `tx.origin`, thus you may submit a script such as:

```
let signedTrxScript = await multicallSign({
  signer,
  chainId,
  calls: [
    // ...
    { to: '0x906f4bD1940737091f18247eAa870D928A85b9Ce', value: 0.01e18 }
  ],
  nonce: 0,
  reqs: [],
  expiry: Date.now() + 1000
});
```

Then you can send this to a searcher, which will submit your transaction script if and only if 0.01 eth is more than the cost of submitting your transaction (e.g. due to gas used at the current gas price).

See [Searcher](#/searcher) for more information.

## Getting Started

For local development or to use the quark-trx tool, simply run `forge build` and `npm install`:

```sh
forge build
```

```sh
cd client && npm install
```

### Details

Quark runs on a few concepts:

* `CodeJar` - An Ethereum contract that stores contract code using `create2` and is easy to load data from.
* `Manifest` - An Ethereum contract to deploy contracts to preknown addresses.
* `Relayer` - The core of Quark- a contract which accepts raw EVM bytecode and executes it from the user's Quark address.

For the most part, you should only be interested in interacting with the Relayer.

When the Relayer receives an Ethereum request it:

 * Checks that the code is in the the Code Jar. If not, it adds it.
 * Next, it takes the address of the code from the Code Jar and associates it with the sender (reverting if data is already set).
 * Next, we deploy a script at the user's Quark address which simply `delegatecall`s to the script in the code jar.
 * We invoke that script with the given calldata.
 * We invoke a special invocation to the Quark address to force it to destruct.

The transaction script sent to the Relayer should effectively be raw EVM opcodes, e.g. `PUSH0; PUSH0; PUSH1 0x55; LOG1`. This will be the script that is invoked during the call from the relayer.

Note: since that script is just a normal script, it can accept callbacks from other contracts, etc. As such, it's important that it's guarded by `relayerOnly` or other protections from inbound calls. The script can rely on the fact that storage at `keccak("org.quark.owner")` (`0x3bb5ebf00f3b539fbe3d28370e5631dd2bb9520dffcea6daf564f94582db8111`) is the owner (underlying wallet) and `keccak("org.quark.relayer")` (`0x46ce4d9fc828e2af4f167362c7c43e310c76adc313cd8fe11e785726f972b4f6`) is the relayer which created this contract.

Note: this currently relies on metamorphic scripts, but it's really not that crucial to the design at this point and may be replaced with a simpler mechanism.

## Copyright

Copyright 2023 Geoffrey Hayes, Mykel Pereira, Compound Labs Inc.
