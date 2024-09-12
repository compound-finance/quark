// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";
import {CodeJarFactory} from "codejar/src/CodeJarFactory.sol";

// Deploy with:
// $ set -a && source .env && ./script/deploy.sh --broadcast

// Required ENV vars:
// RPC_URL
// DEPLOYER_PK

// Optional ENV vars:
// ETHERSCAN_KEY

contract DeployCodeJarFactory is Script {
    CodeJarFactory codeJarFactory;
    CodeJar codeJar;

    function run() public {
        address deployer = vm.addr(vm.envUint("DEPLOYER_PK"));

        vm.startBroadcast(deployer);

        console.log("=============================================================");

        console.log("Deploying Code Jar Factory");
        codeJarFactory = new CodeJarFactory();
        codeJar = codeJarFactory.codeJar();
        console.log("Code Jar Factory Deployed:", address(codeJarFactory));
        console.log("Code Jar Deployed:", address(codeJar));

        console.log("=============================================================");

        vm.stopBroadcast();
    }
}
