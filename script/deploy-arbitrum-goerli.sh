#!/bin/bash

set -ex

echo "Deploying Quark to Arbitrum Goerli"
cast send --interactive --chain 421613 --rpc-url https://goerli-rollup.arbitrum.io/rpc --create "$(cat out/Quark.yul/Quark.json | jq -r .bytecode.object)"
