
## Quark

Turn every Ethereum EOA into a smart contract wallet. Quark uses [metamorphic contracts](https://0age.medium.com/the-promise-and-the-peril-of-metamorphic-contracts-9eb8b8413c5e) to create a virtual account associated with your EOA which can send arbitrary logic with each transaction. Say you want to buy and sell two assets on Uniswap atomically: you can send that in a quark transaction without deploying a smart contract. You can then turn around and send another transaction from the same account that supplies atomically to two DeFi protocols. Quark brings the idea of "transaction scripts" to Ethereum and removes the need of using "smart contract wallets" to manage positions.

## How it works

Quark uses metamorphic contracts-- that is, contracts made using `CREATE2` that have dynamic code. Specifically, quark deploys a contract for each transaction you make and then forces it to `SELFDESTRUCT`, freeing it up for new logic for your next transaction.

Note, your transactions won't come from your EOA address directly-- but they will come from an address derived from your EOA. Thus you can think of each EOA having a second address (its quark address) that effectively becomes your new address. This should act like a normal Ethereum address from your perspective, though you won't be able to sign messages from it.

To send a Quark transaction, you simply send the EVM code that you want to run to the Quark Relayer contract. E.g.

```json
{ "to": "0xQuarkRelayer", "data": "{evm bytecode}" }
```

That code will run as a transaction script in your quark address, performing whatever operations you've specified (e.g. trading on Uniswap, etc). There is no trust being granted to Quark (aside of code bugs), and the Quark Relayer itself is not upgradable.

## Using Quark

There's nothing to do-- you can simply start sending Quark transactions today.

| Network       | Quark Relayer |
| ------------- | ------------- |
| Goerli        | 0x...         |

You can send scripts through a dApp, but they are simply data, so you can even send this via MetaMask. Try sending these transaction scripts on Goerli:

#### Log a Message

This script will simply emit a log message which you can see in Etherscan.

```hex
0x30303050505060376080527f48257dc961b6f792c2b78a080dacfed693b660960a702de21cee364e20270e2f60206080a100
```

#### Atomic Buy and Sell on Uniswap

This script will...

```hex
0x303030505050...
```

## Writing Transaction Scripts

For Quark to be exciting, you need to be able to write your own transaction scripts. There are two ways of doing this: 1) write a script directly in YUL, which is Solidity's intermediate representation, or 2) experimentally, write a script in Solidity and convert a given function into a transactoin script.

### Transaction Scripts

Transaction scripts are simply EVM bytecode. E.g. `60006000A0` is the bytecode `PUSH 0; PUSH 0; LOG0`. When run, this will be executed in the context of your quark address.

Transaction scripts **should not** be full Solidity contracts-- this will likely revert or have no effect. Instead, they should be a fine-tuned set of instructions to run directly (think of it as a function, not a contract).

Transaction scripts _must start with the magic header 0x303030505050_ (`ADDRESS; ADDRESS; ADDRESS; POP; POP; POP;`), and this magic header must be valid as part of your transaction script. This is a technical limitation as we need to ensure your quark address self destructs after its run, or you account would become locked.

Note: storage(0) is reserved for the user's true EOA account, storage(1) is for the relayer and storage(2) is also reserved. Aside of that, you can use any storage or memory you'd lile.

### YUL

Here's an example script in YUL:

```as
object "Logger" {
  code {
    verbatim_0i_0o(hex"303030505050")

    // Store a value (55) in memory
    mstore(0x80, 55)

    // ABI topic for `Ping(uint256)`
    let topic := 0x48257dc961b6f792c2b78a080dacfed693b660960a702de21cee364e20270e2f

    // emit Ping(55)
    log1(0x80, 0x20, topic)

    return(0, 0)
  }
}
```

In that code, we emit a simple Ethereum log. The compiled bytecode looks like this:

```
0x30303050505060376080527f48257dc961b6f792c2b78a080dacfed693b660960a702de21cee364e20270e2f60206080a100
```

This is a valid transaction script and can be sent to the Quark Relayer.

### Solidity

There is _very experimental_ support for turning a Solidity contract into a transaction script. Currently, you should build a Solidity contract as so:

```rs
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract Fun {
  event FunTimes(uint256);

  function hello() external {
    emit FunTimes(55);
  }
}
```

Then compile the contract to ir, e.g.:

```sh
forge build --extra-output ir --extra-output-files ir --via-ir
```

Make sure npm is installed:

```sh
npm install
```

Finally, run the capture script specifying the name of the contract and name of the function you can to run:

```sh
node script/capture.mjs Fun hello
```

This should (may?) return bytecode that should (might?) work as a transaction script. There is a lot of work to be done on how to create minimal scripts as its not previously been a common use-case of Solidity. That said, any language that could compile to Yul, for instance, could be used and it would be cool to see a simple Transaction Script language built.

## Testing

You can run tests by running:

```sh
forge test
```

## Technical Limitations

The magic incantation (0x303030505050) works well, but is a bit of a hassle. Specifically, we want to modify the user's transaction script to begin with "if second invokation, self destruct." But if you insert an opcode before the user's own script, everything gets shifted in the pc. That would be okay, except JUMPs in the EVM are absolute and thus we need to update the user's transaction script to know the shift. But doing so would shift downstream JUMPs and so the only way to accomplish this is with a very complex jump table that lives in the updated runtime. This is on the list of things to do, but as we don't have a good way to create transaction scripts currently anyway, got pushed back.

Also, [SELFDESTRUCT is going away] and thus transaction scripts might not live on forever :(

## Copyright

Copyright 2023 Geoffrey Hayes, Mykel Pereira, Compound Labs Inc.
