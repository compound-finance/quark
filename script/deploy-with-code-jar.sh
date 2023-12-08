#!/bin/bash

set -eo pipefail

# Initialize variables
code_jar="0xcA85333B65E86d114e2bd5b4aE23Fe6E6a3Ae8e3"
contract=""
constructor_abi=""
constructor_args=()
rpc_url="$RPC_URL"
dry_run=false
deployer_key="$DEPLOYER_KEY"
extra_args=()

while true; do
  echo "x=|${1}|"
  if   [[ ${1} =~ ^-(j|-code-jar)$ ]]; then code_jar=${2}; shift 2;
  elif [[ ${1} =~ ^-(c|-contract)$  ]]; then contract=${2}; shift 2;
  elif [[ ${1} =~ ^-(r|-rpc-url)$ ]]; then rpc_url=${2}; shift 2;
  elif [[ ${1} =~ ^-(d|-dry-run)$ ]]; then dry_run=true; shift 1;
  elif [[ ${1} =~ ^-(k|-deployer-key)$ ]]; then deployer_key=${2}; shift 2;
  elif [[ ${1} =~ ^-(a|-constructor)$ ]]; then
    constructor_abi=${2}
    while [[ ! ${3} =~ ^- ]]; do
      constructor_args+=(${3})
      shift 1;
    done

    shift 2;
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

# Your script logic here
echo "Code Jar: $code_jar"
echo "Contract: $contract"
echo "Constructor ABI: $constructor_abi"
echo "Constructor Args: ${constructor_args[*]}"
echo "Dry Run: $dry_run"
echo "RPC Url: $rpc_url"
echo "Additional Arguments: ${extra_args[@]}"

# Check for required arguments and display usage
if [ -z "$code_jar" ] || [ -z "$contract" ] || [ -z "$deployer_key" ] || [ -z "$rpc_url" ]; then
    echo "Error: Missing required arguments."
    echo ""
    echo "Usage: $0 [-c|--contract CONTRACT_NAME] [-k|--deployer-key DEPLOYER_KEY] [-j|--code-jar CODE_JAR] [-a|--constructor CONSTRUCTOR_ABI ...CONSTRUCTOR_ARGS] [-d|--dry-run] [-r|--rpc-url RPC_URL] -- [ADDITIONAL ARGS...]"
    echo "  -c, --contract     Specify the contract name to deploy (either \`MyContract\` or \`./out/MyContract.json/MyContract.sol\`)."
    echo "  -k, --deployer-key Specify the deployer private key (env: \$DEPLOYER_KEY)."
    echo "  -j, --code-jar     Specify the Code Jar address (default: 0x7fcdb6ef7d39acf15b0d376ee6a7a8658d5624b6)."
    echo "  -r, --rpc-url      Specify the Ethereum RPC url (env: \$RPC_URL)"
    echo "  -a, --constructor  Specify the constructor (e.g. \`-a \"(address,uint256)\" \"(0x0011223344556677889900112233445566778899,55)\"\`)."
    echo "  -d, --dry-run      Run in dry run mode."
    echo ""
    echo "Additional forge arguments can be provided after '--'."
    exit 1
fi

if [ -n "$constructor_abi" ]; then
  if ! command -v cast &> /dev/null
  then
    echo "Error: missing required \`cast\` tool for encoding ABI arguments"
    echo ""
    exit 1
  fi

  if [[ ${constructor_abi} =~ ^[[:alnum:]_]\([[:alnum:]_,]+\)$ ]]; then
    constructor_abi="$constructor_abi"
    # ok
  elif [[ ${constructor_abi} =~ ^\([[:alnum:]_,]+\)$ ]]; then
    constructor_abi="cons$constructor_abi"
  elif [[ ${constructor_abi} =~ ^[[:alnum:]_,]+$ ]]; then
    constructor_abi="cons($constructor_abi)"
  else
    echo "Invalid constructor abi: \"$constructor_abi\""
  fi

  echo "constructor_abi=$constructor_abi"

  constructor="$(cast abi-encode "$constructor_abi" ${constructor_args[*]})"
fi

if [ ! -f "$contract" ]; then
  contract_out="./out/$contract.sol/$contract.json"
  if [ ! -f "$contract_out" ]; then
    echo "Unknown contract: $contract"
    exit 1
  fi
  contract="$contract_out"
fi

# if [ -n "$ETHERSCAN_KEY" ]; then
#   etherscan_args="--verify --etherscan-api-key $ETHERSCAN_KEY"
# else
#   etherscan_args=""
# fi

DRY_RUN="$dry_run" \
  CODE_JAR="$code_jar" \
  CONSTRUCTOR_ARGS="$constructor" \
  METADATA="" \
  DEPLOYER_PK="$deployer_key" \
  CONTRACT="$contract" \
  forge script \
    --optimize \
    --broadcast \
    --rpc-url "$rpc_url" \
    $@ \
    script/CodeJarDeployer.s.sol:DeployWithCodeJar
 