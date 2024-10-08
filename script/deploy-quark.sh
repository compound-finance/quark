#!/bin/bash

set -exo pipefail

if [ -n "$RPC_URL" ]; then
  rpc_args="--rpc-url $RPC_URL"
else
  rpc_args=""
fi

if [ -n "$DEPLOYER_PK" ]; then
  wallet_args="--private-key $DEPLOYER_PK"
else
  wallet_args="--unlocked"
fi

if [ -n "$ETHERSCAN_KEY" ]; then
  etherscan_args="--verify --etherscan-api-key $ETHERSCAN_KEY"
else
  etherscan_args=""
fi

FOUNDRY_PROFILE=ir forge script \
    $rpc_args \
    $wallet_args \
    $etherscan_args \
    $@ \
    script/DeployQuarkWalletFactory.s.sol:DeployQuarkWalletFactory

repo_root=$(git rev-parse --show-toplevel)
${repo_root}/script/prepare-release.sh
