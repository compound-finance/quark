#!/bin/bash

set -e

if [ -z "$QUARKNET_PRIVATE_KEY" ]; then
  echo "Please set QUARK_NET_PRIVATE_KEY"
  exit 1
fi

RPC_URL="https://ethforks.io/@quark"
PRIVATE_KEY="$QUARKNET_PRIVATE_KEY"

echo "Deploying Quark to Quark net"
forge create src/Relayer.sol:Relayer --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL"

# Deployer: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
# Deployed to: 0x687bB6c57915aa2529EfC7D2a26668855e022fAE
# Transaction hash: 0x6fbe481b4bf0f775fa8abe323d954e5c861eac18053609f85e23df89512c00e4
