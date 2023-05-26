#!/bin/bash

set -ex

echo "Deploying Quark to Optimism Goerli"
cast send --interactive --chain 420 --rpc-url https://goerli.optimism.io --create "$(cat out/Quark.yul/Quark.json | jq -r .bytecode.object)"
