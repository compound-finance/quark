#!/bin/bash

set -e
script_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "$script_dir/.."

network=$1
relayer=$2
script=$3

function print_usage() {
  echo "script/create_core_scripts.sh {network} {relayer_address} [{script}]"
  exit 1
}

key_arg="--interactive"

if [ -z "$relayer" ]; then
  print_usage
fi

case "$network" in
  arbitrum-goerli)
    [ -n "$ARBITRUM_GOERLI_DEPLOYER_KEY" ] && key_arg="--private-key $ARBITRUM_GOERLI_DEPLOYER_KEY"
    rpc_url="https://goerli-rollup.arbitrum.io/rpc"
    network_name="Arbitrum [Goerli]"
    ;;
  arbitrum-mainnet)
    [ -n "$ARBITRUM_DEPLOYER_KEY" ] && key_arg="--private-key $ARBITRUM_DEPLOYER_KEY"
    rpc_url=""https://arb1.arbitrum.io/rpc""
    network_name="Arbitrum [Mainnet]"
    ;;
  goerli)
    [ -n "$GOERLI_DEPLOYER_KEY" ] && key_arg="--private-key $GOERLI_DEPLOYER_KEY"
    rpc_url="https://goerli-eth.compound.finance"
    network_name="Goerli"
    ;;
  optimism-goerli)
    [ -n "$OPTIMISM_GOERLI_DEPLOYER_KEY" ] && key_arg="--private-key $OPTIMISM_GOERLI_DEPLOYER_KEY"
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
    network_name="Localhost"
    ;;
  "")
    print_usage
    ;;
  *)
    echo "invalid network '$network'. valid networks: arbitrum-goerli, arbitrum-mainnet, goerli, optimism-goerli, quarknet, local"
    print_usage
    ;;
esac

echo "--- ${date}"
echo "Creating core scripts on $network_name"

for full_script_file in ${script:-core_scripts/*.sol}; do
  script_file="${full_script_file##*/}"
  contract_name="${script_file%.*}"
  bytes=$(cat out/$script_file/$contract_name.json | jq -r .deployedBytecode.object)

  echo "Creating core scripts $contract_name"

  cast send $key_arg --rpc-url "$rpc_url" "$relayer" "saveQuarkCode(bytes)(address)" "$bytes"
done
