// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {CodeJar} from "quark-core/src/CodeJar.sol";
import {CodeJarFactory} from "quark-core/src/CodeJarFactory.sol";
import {BatchExecutor} from "quark-core/src/periphery/BatchExecutor.sol";
import {QuarkWalletFactory} from "quark-core/src/QuarkWalletFactory.sol";

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
    QuarkWalletFactory quarkWalletFactory;
    BatchExecutor batchExecutor;
    Ethcall ethcall;
    Multicall multicall;

    function run() public {
        address deployer = vm.addr(vm.envUint("DEPLOYER_PK"));

        vm.startBroadcast(deployer);

        console.log("=============================================================");
        console.log("Deploying CodeJar");

        CodeJarFactory codeJarFactory = new CodeJarFactory();
        CodeJar codeJar = codeJarFactory.codeJar();

        console.log("=============================================================");
        console.log("Deploying QuarkWalletFactory");

        quarkWalletFactory = new QuarkWalletFactory(codeJar);

        console.log("QuarkWalletFactory Deployed:", address(quarkWalletFactory));

        console.log("Deploying BatchExecutor");

        batchExecutor = new BatchExecutor();

        console.log("BatchExecutor Deployed:", address(batchExecutor));

        console.log("Deploying Core Scripts");

        ethcall = Ethcall(codeJar.saveCode(vm.getDeployedCode(string.concat("out/", "Ethcall.sol/Ethcall.json"))));
        console.log("Ethcall Deployed:", address(ethcall));

        multicall =
            Multicall(codeJar.saveCode(vm.getDeployedCode(string.concat("out/", "Multicall.sol/Multicall.json"))));
        console.log("Multicall Deployed:", address(multicall));

        console.log("=============================================================");

        vm.stopBroadcast();
    }
}
