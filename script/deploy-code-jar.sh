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

forge script --via-ir \
    $rpc_args \
    $wallet_args \
    $etherscan_args \
    $@ \
    script/DeployCodeJarFactory.s.sol:DeployCodeJarFactory
