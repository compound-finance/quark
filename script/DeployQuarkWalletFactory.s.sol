// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {BatchExecutor} from "quark-core/src/periphery/BatchExecutor.sol";
import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";

import {QuarkWalletProxyFactory} from "quark-proxy/src/QuarkWalletProxyFactory.sol";

import {Ethcall} from "quark-core-scripts/src/Ethcall.sol";
import {Multicall} from "quark-core-scripts/src/Multicall.sol";

// Deploy with:
// $ set -a && source .env && ./script/deploy.sh --broadcast

// Required ENV vars:
// RPC_URL
// DEPLOYER_PK

// Optional ENV vars:
// ETHERSCAN_KEY

contract DeployQuarkWalletFactory is Script {
    QuarkWalletProxyFactory quarkWalletProxyFactory;
    BatchExecutor batchExecutor;
    Ethcall ethcall;
    Multicall multicall;

    function run() public {
        address deployer = vm.addr(vm.envUint("DEPLOYER_PK"));

        vm.startBroadcast(deployer);

        console.log("=============================================================");
        console.log("Deploying QuarkWalletProxyFactory");

        quarkWalletProxyFactory =
            new QuarkWalletProxyFactory(address(new QuarkWallet(new CodeJar(), new QuarkStateManager())));

        console.log("QuarkWalletProxyFactory Deployed:", address(quarkWalletProxyFactory));

        console.log("Deploying BatchExecutor");

        batchExecutor = new BatchExecutor();

        console.log("BatchExecutor Deployed:", address(batchExecutor));

        console.log("Deploying Core Scripts");

        CodeJar codeJar = QuarkWallet(payable(quarkWalletProxyFactory.walletImplementation())).codeJar();

        ethcall = Ethcall(codeJar.saveCode(vm.getDeployedCode(string.concat("out/", "Ethcall.sol/Ethcall.json"))));
        console.log("Ethcall Deployed:", address(ethcall));

        multicall =
            Multicall(codeJar.saveCode(vm.getDeployedCode(string.concat("out/", "Multicall.sol/Multicall.json"))));
        console.log("Multicall Deployed:", address(multicall));

        console.log("=============================================================");

        vm.stopBroadcast();
    }
}
