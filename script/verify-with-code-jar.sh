#!/bin/bash

set -eo pipefail

cons=`cat <<-EOM
    constructor(bytes memory code) {
        assembly {
            return(add(code, 0x20), mload(code))
        }
    }
EOM`

# Initialize variables
chain=""
contract=""
address=""
etherscan_key="$ETHERSCAN_KEY"
extra_args=()

while true; do
  echo "x=|${1}|"
  if [[ ${1} =~ ^-(n|-network)$  ]]; then chain=${2}; shift 2;
  elif [[ ${1} =~ ^-(c|-contract)$  ]]; then contract=${2}; shift 2;
  elif [[ ${1} =~ ^-(@|-address)$  ]]; then address=${2}; shift 2;
  elif [[ ${1} =~ ^-(k|-etherscan-key)$  ]]; then etherscan_key=${2}; shift 2;
  elif [[ ${1} =~ ^--$ ]]; then
    while [ -n ${1} ]; do
      extra_args+=(${1})
      shift
    done
  elif [[ ${1} =~ ^$ ]]; then
    break
  else
    >&2 printf 'Invalid flag: %s\n' ${1}
    exit 1
  fi
done

contract_deployed="${contract}Deployed"

# Your script logic here
echo "Chain: $chain"
echo "Contract: $contract"
echo "Contract Deployed: $contract_deployed"
echo "Address: $address"
echo "Etherscan Key: $etherscan_key"
echo "Additional Arguments: ${extra_args[@]}"

# Check for required arguments and display usage
if [ -z "$chain" ] || [ -z "$contract" ] || [ -z "$address" ] || [ -z "$etherscan_key" ]; then
    echo "Error: Missing required arguments."
    echo ""
    echo "Usage: $0 [-c|--contract CONTRACT_NAME] [-@|--address ADDRESS] [-k|--etherscan-key ETHERSCAN_KEY] [-n|--network NETWORK] -- [ADDITIONAL ARGS...]"
    echo "  -c, --contract      Specify the contract name to deploy (e.g. \`MyContract\`)."
    echo "  -@, --address       Specify the contract deployment address."
    echo "  -n, --network       Specify the network to use (e.g. goerli)."
    echo "  -k, --etherscan-key Specify the Etherscan API key to use (env: \$ETHERSCAN_KEY)"
    echo ""
    echo "Additional forge arguments can be provided after '--'."
    exit 1
fi

contract_out="./out/$contract.sol/$contract.json"
if [ ! -f "$contract_out" ]; then
  echo "Unknown contract: $contract"
  exit 1
fi

deployed_code="$(cat "$contract_out" | jq -r .deployedBytecode.object)" # TODO: Check if empty
constructor_args=`cast abi-encode "cons(bytes)" $deployed_code`

contract_src="./src/codejar/src/$contract.sol"
contract_deployed_src="./src/deployed/${contract_deployed}.sol"

cat "$contract_src" \
  | sed -E "s!(contract $contract.*{)!\\1\n${cons//$'\n'/\\n}!" \
  | sed -E "s!contract $contract!contract ${contract_deployed}!" \
  > "$contract_deployed_src"

forge build --via-ir

forge verify-contract \
    --watch \
    --chain "$chain" \
    --etherscan-api-key "$etherscan_key" \
    "$address" \
    "$contract_deployed" \
    --constructor-args "$constructor_args" \
    $@ \