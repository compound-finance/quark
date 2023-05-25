#!/bin/bash

set -ex

echo "Deploying Quark to Goerli"
cast send --interactive --chain goerli --rpc-url https://goerli-eth.compound.finance --create "$(cat out/Quark.yul/Quark.json | jq -r .bytecode.object)"
