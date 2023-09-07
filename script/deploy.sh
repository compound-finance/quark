#!/bin/bash

set -eo pipefail
script_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "$script_dir/.."

network=$1

function print_usage() {
  echo "script/deploy.sh {network}"
  exit 1
}

key_arg="--interactive"
extra_args=""

case "$network" in
  arbitrum-goerli)
    [ -n "$ARBITRUM_GOERLI_DEPLOYER_KEY" ] && key_arg="--private-key $ARBITRUM_GOERLI_DEPLOYER_KEY"
    extra_args="--verify"
    if [ -n "ARBISCAN_API_KEY" ]; then
      export ETHERSCAN_API_KEY="$ARBISCAN_API_KEY"
    fi
    rpc_url="https://goerli-rollup.arbitrum.io/rpc"
    network_name="Arbitrum [Goerli]"
    ;;
  arbitrum-mainnet)
    [ -n "$ARBITRUM_DEPLOYER_KEY" ] && key_arg="--private-key $ARBITRUM_DEPLOYER_KEY"
    extra_args="--verify"
    if [ -n "ARBISCAN_API_KEY" ]; then
      export ETHERSCAN_API_KEY="$ARBISCAN_API_KEY"
    fi
    rpc_url=""https://arb1.arbitrum.io/rpc""
    network_name="Arbitrum [Mainnet]"
    ;;
  goerli)
    [ -n "$GOERLI_DEPLOYER_KEY" ] && key_arg="--private-key $GOERLI_DEPLOYER_KEY"
    extra_args="--verify"
    rpc_url="https://goerli-eth.compound.finance"
    network_name="Goerli"
    ;;
  optimism-goerli)
    [ -n "$OPTIMISM_GOERLI_DEPLOYER_KEY" ] && key_arg="--private-key $OPTIMISM_GOERLI_DEPLOYER_KEY"
    if [ -n "OPTIMISM_API_KEY" ]; then
      export ETHERSCAN_API_KEY="$OPTIMISM_API_KEY"
    fi
    extra_args="--verify"
    rpc_url="https://goerli.optimism.io"
    network_name="Optimism [Goerli]"
    ;;
  quarknet)
    [ -n "$QUARKNET_DEPLOYER_KEY" ] && key_arg="--private-key $QUARKNET_DEPLOYER_KEY"
    rpc_url="https://ethforks.io/@quark"
    network_name="Quarknet"
    ;;
  local)
    key_arg="--private-key ${LOCAL_DEPLOYER_KEY:-"0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"}"
    rpc_url="http://localhost:8545"
    network_name="localhost"
    ;;
  "")
    print_usage
    ;;
  *)
    echo "invalid network '$network'. valid networks: arbitrum-goerli, arbitrum-mainnet, goerli, optimism-goerli, quarknet, local"
    print_usage
    ;;
esac

shift
echo "--- ${date}"
echo "Builind Quark..."
script/build
echo "Deploying Quark to $network_name"
forge script script/Deploy.s.sol:DeployScript $key_arg --rpc-url "$rpc_url" $extra_args $@
