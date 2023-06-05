#!/bin/bash

set -e

if [ -z "$GOERLI_PRIVATE_KEY" ]; then
  echo "Please set GOERLI_PRIVATE_KEY"
  exit 1
fi

RPC_URL="https://goerli-eth.compound.finance"
PRIVATE_KEY="$GOERLI_PRIVATE_KEY"

echo "Deploying Quark to Quark net"
forge create src/Relayer.sol:Relayer --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL"
