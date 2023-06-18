#!/bin/bash

set -eo pipefail
script_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "$script_dir/.."

network=$1
relayer_type="kafka"

function print_usage() {
  echo "script/deploy.sh {network}"
  exit 1
}

key_arg="--interactive"
extra_args=""

case "$relayer_type" in
  kafka)
    contract="src/RelayerKafka.sol:RelayerKafka"
    ;;
  *)
    echo "invalid relayer type '$relayer_type'. valid relayer types: kafka"
    print_usage
    ;;
esac

case "$network" in
  arbitrum-goerli)
    [ -n "$ARBITRUM_GOERLI_DEPLOYER_KEY" ] && key_arg="--private-key $ARBITRUM_GOERLI_DEPLOYER_KEY"
    extra_args="--verify"
    if [ -n "ARBISCAN_API_KEY" ]; then
      export ETHERSCAN_API_KEY="$ARBISCAN_API_KEY"
    fi
    rpc_url="https://goerli-rollup.arbitrum.io/rpc"
    network_name="Arbitrum [Goerli]"
    deployments_json="deployments.json"
    ;;
  arbitrum-mainnet)
    [ -n "$ARBITRUM_DEPLOYER_KEY" ] && key_arg="--private-key $ARBITRUM_DEPLOYER_KEY"
    extra_args="--verify"
    if [ -n "ARBISCAN_API_KEY" ]; then
      export ETHERSCAN_API_KEY="$ARBISCAN_API_KEY"
    fi
    rpc_url=""https://arb1.arbitrum.io/rpc""
    network_name="Arbitrum [Mainnet]"
    deployments_json="deployments.json"
    ;;
  goerli)
    [ -n "$GOERLI_DEPLOYER_KEY" ] && key_arg="--private-key $GOERLI_DEPLOYER_KEY"
    extra_args="--verify"
    rpc_url="https://goerli-eth.compound.finance"
    network_name="Goerli"
    deployments_json="deployments.json"
    ;;
  optimism-goerli)
    [ -n "$OPTIMISM_GOERLI_DEPLOYER_KEY" ] && key_arg="--private-key $OPTIMISM_GOERLI_DEPLOYER_KEY"
    if [ -n "OPTIMISM_API_KEY" ]; then
      export ETHERSCAN_API_KEY="$OPTIMISM_API_KEY"
    fi
    extra_args="--verify"
    rpc_url="https://goerli.optimism.io"
    network_name="Optimism [Goerli]"
    deployments_json="deployments.json"
    ;;
  quarknet)
    [ -n "$QUARKNET_DEPLOYER_KEY" ] && key_arg="--private-key $QUARKNET_DEPLOYER_KEY"
    rpc_url="https://ethforks.io/@quark"
    network_name="Quarknet"
    deployments_json="deployments.json"
    ;;
  local)
    key_arg="--private-key ${LOCAL_DEPLOYER_KEY:-"0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"}"
    rpc_url="http://localhost:8545"
    network_name="localhost"
    deployments_json="deployments.local.json"
    if [ ! -f "$deployments_json" ]; then
      echo "{}" > "$deployments_json"
    fi

    ;;
  "")
    print_usage
    ;;
  *)
    echo "invalid network '$network'. valid networks: arbitrum-goerli, arbitrum-mainnet, goerli, optimism-goerli, quarknet, local"
    print_usage
    ;;
esac

code_jar_key=".$network.codeJar"
code_jar="$(cat "$deployments_json" | jq -r "$code_jar_key // \"0x0000000000000000000000000000000000000000\"")"

shift
echo "--- ${date}"
echo "Deploying Quark to $network_name with code_jar=${code_jar}"
res="$(forge create "$contract" --optimize --optimizer-runs 200 $key_arg --rpc-url "$rpc_url" $extra_args --json --constructor-args "$code_jar" $@)"
echo "$res"

relayer_address="$(echo "$res" | jq '.deployedTo')"

tmp="$(mktemp)"
jq \
  ".$network.Relayer = $relayer_address" "$deployments_json" > "$tmp" && mv "$tmp" "$deployments_json"

echo ""
