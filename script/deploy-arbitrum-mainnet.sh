#!/bin/bash

set -ex

echo "Deploying Quark to Arbitrum Mainnet"
cast send --interactive --chain 42161 --rpc-url https://arb1.arbitrum.io/rpc --create "$(cat out/Quark.yul/Quark.json | jq -r .bytecode.object)"
