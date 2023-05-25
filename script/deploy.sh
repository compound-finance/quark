#!/bin/bash

set -ex

# TODO: Load contract code directly
# TODO: Private key

PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
RPC_URL="https://ethforks.io/@bowed-task"

echo "Deploying Quark"
cast send --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL" --create "$(cat out/Quark.yul/Quark.json | jq -r .bytecode.object)"

echo "Deploying Counter"
forge create src/Counter.sol:Counter --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL"


# cast call --rpc-url "https://ethforks.io/@bowed-task" "0x85495222Fd7069B987Ca38C2142732EbBFb7175D" "number()(uint256)"
# cast send --private-key "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" --rpc-url "https://ethforks.io/@bowed-task" "0xC220Ed128102d888af857d137a54b9B7573A41b2" "0x30303050505060008054808280a180608814605e576099146054575b63d09de08a608052806004609c827385495222fd7069b987ca38c2142732ebbfb7175d8180858582855af1508180858582855af1505af1005b6199998180a1601b565b506188888180a1601b56"


# cast send --private-key "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" --rpc-url "https://ethforks.io/@bowed-task" "0xE2b5bDE7e80f89975f7229d78aD9259b2723d11F" "0x303030505050600b6072565b60af565b5f604051905090565b5f819050919050565b5f819050919050565b5f819050919050565b5f60476043603f846018565b602a565b6021565b9050919050565b6055816033565b82525050565b5f602082019050606c5f830184604e565b92915050565b60377fa1591fde914eeec9b1f4af5ae4aa02e5df4a18be175afa9203f1307f5053151a609b600f565b60a38382605b565b8282820383a150505050565bfea2646970667358221220629b57fc7a55856d943109f0e940d27c46651513e6d6b4ebf79b81c39234f0fd64736f6c63430008110033"

