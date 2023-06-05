#!/bin/bash

set -e

if [ -z "$QUARKNET_DEPLOYER_KEY" ]; then
  echo "Please set QUARKNET_DEPLOYER_KEY"
  exit 1
fi

RPC_URL="https://ethforks.io/@quark"
DEPLOYER_KEY="$QUARKNET_DEPLOYER_KEY"

echo "Deploying Quark to Quark net"
forge create src/Relayer.sol:Relayer --private-key "$DEPLOYER_KEY" --rpc-url "$RPC_URL"
