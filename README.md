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
