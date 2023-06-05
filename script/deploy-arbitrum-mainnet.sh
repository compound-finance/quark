#!/bin/bash

set -e

if [ -z "$ARBITRUM_PRIVATE_KEY" ]; then
  echo "Please set ARBITRUM_PRIVATE_KEY"
  exit 1
fi

RPC_URL="https://arb1.arbitrum.io/rpc"
PRIVATE_KEY="$ARBITRUM_PRIVATE_KEY"

echo "Deploying Quark to Quark net"
forge create src/Relayer.sol:Relayer --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL"
