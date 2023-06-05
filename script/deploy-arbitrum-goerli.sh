#!/bin/bash

set -e

if [ -z "$ARBITRUM_GOERLI_PRIVATE_KEY" ]; then
  echo "Please set ARBITRUM_GOERLI_PRIVATE_KEY"
  exit 1
fi

RPC_URL="https://goerli-rollup.arbitrum.io/rpc"
PRIVATE_KEY="$ARBITRUM_GOERLI_PRIVATE_KEY"

echo "Deploying Quark to Quark net"
forge create src/Relayer.sol:Relayer --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL"
