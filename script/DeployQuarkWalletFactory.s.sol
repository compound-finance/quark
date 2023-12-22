// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {BatchExecutor} from "quark-core/src/periphery/BatchExecutor.sol";
import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";

import {QuarkWalletProxyFactory} from "quark-proxy/src/QuarkWalletProxyFactory.sol";
import {QuarkFactory} from "quark-factory/src/QuarkFactory.sol";
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
    QuarkFactory quarkFactory;

    function run() public {
        address deployer = vm.addr(vm.envUint("DEPLOYER_PK"));

        vm.startBroadcast(deployer);

        console.log("=============================================================");

        console.log("Deploying Quark Factory");
        quarkFactory = new QuarkFactory();
        console.log("Quark Factory Deployed:", address(quarkFactory));

        console.log("Deploying Quark Contracts via Quark Factory");
        quarkFactory.deployQuarkContracts();
        console.log("Code Jar Deployed:", address(quarkFactory.codeJar()));
        console.log("Quark State Manager Deployed:", address(quarkFactory.quarkStateManager()));
        console.log("Quark Wallet Implementation Deployed:", address(quarkFactory.quarkWalletImpl()));
        console.log("Quark Wallet Proxy Factory Deployed:", address(quarkFactory.quarkWalletProxyFactory()));
        console.log("Batch Executor Deployed:", address(quarkFactory.batchExecutor()));

        console.log("Deploying Core Scripts");

        CodeJar codeJar = QuarkWallet(payable(quarkFactory.quarkWalletProxyFactory().walletImplementation())).codeJar();

        ethcall = Ethcall(codeJar.saveCode(vm.getDeployedCode(string.concat("out/", "Ethcall.sol/Ethcall.json"))));
        console.log("Ethcall Deployed:", address(ethcall));

        multicall =
            Multicall(codeJar.saveCode(vm.getDeployedCode(string.concat("out/", "Multicall.sol/Multicall.json"))));
        console.log("Multicall Deployed:", address(multicall));

        console.log("=============================================================");

        vm.stopBroadcast();
    }
}
