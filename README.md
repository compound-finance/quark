# Quark

## Overview

Quark is a wallet system which allows users to run arbitrary code ("Quark operations") specific to each Ethereum transaction. Think of a Quark wallet as an Ethereum proxy contract that updates itself each transaction. This is accomplished by the Quark wallet making a delegate call to a contract which has the code it wants to run on that invocation. We use Code Jar to deploy these Quark-runnable contracts using create2 to make code reuse efficient. Finally, we have a factory system to create wallets at pre-determined address and a set of Core Scripts which are audited contract codes as a template for Quark operations.

## Fork tests and NODE_PROVIDER_BYPASS_KEY

Some tests require forking mainnet, e.g. to exercise use-cases like
supplying and borrowing in a comet market.

For a "fork url" we use our rate-limited node provider endpoint at
`https://node-provider.compound.finance/ethereum-mainnet`. Setting up a
fork quickly exceeds the rate limits, so we use a bypass key to allow fork
tests to exceed the rate limits.

A bypass key for Quark development can be found in 1Password as a
credential named "Quark Dev node-provider Bypass Key". The key can then be
set during tests via the environment variable `NODE_PROVIDER_BYPASS_KEY`,
like so:

```
$ NODE_PROVIDER_BYPASS_KEY=... forge test
```

## Updating gas snapshots

In CI we compare gas snapshots against a committed baseline (stored in
`.gas-snapshot`), and the job fails if any diff in the snapshot exceeds a
set threshold from the baseline.

You can accept the diff and update the baseline if the increased gas usage
is intentional. Just run the following command:

```sh
$ NODE_PROVIDER_BYPASS_KEY=... forge snapshot
```

Then commit the updated snapshot file:

```sh
$ git add .gas-snapshot && git commit -m "commit new baseline gas snapshot"
```
