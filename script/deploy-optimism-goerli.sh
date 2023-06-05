#!/bin/bash

set -e

args=--interactive
if [ -n "$OPTIMISM_GOERLI_DEPLOYER_KEY" ]; then
  args=--private-key "$OPTIMISM_GOERLI_DEPLOYER_KEY"
fi

RPC_URL="https://goerli.optimism.io"

echo "Deploying Quark to Quark net"
forge create src/Relayer.sol:Relayer --rpc-url "$RPC_URL" $args $@
