// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {CodeJar} from "../src/CodeJar.sol";
import {QuarkWalletFactory} from "../src/QuarkWalletFactory.sol";
import {Ethcall} from "../src/core_scripts/Ethcall.sol";
import {Multicall} from "../src/core_scripts/Multicall.sol";

// Deploy with:
// $ set -a && source .env && ./script/deploy.sh --broadcast

// Required ENV vars:
// RPC_URL
// DEPLOYER_PK

// Optional ENV vars:
// ETHERSCAN_KEY

contract DeployQuarkWalletFactory is Script {
    QuarkWalletFactory quarkWalletFactory;
    Ethcall ethcall;
    Multicall multicall;

    function run() public {
        address deployer = vm.addr(vm.envUint("DEPLOYER_PK"));

        vm.startBroadcast(deployer);

        console.log("=============================================================");
        console.log("Deploying QuarkWalletFactory");

        quarkWalletFactory = new QuarkWalletFactory();

        console.log("QuarkWalletFactory Deployed:", address(quarkWalletFactory));

        console.log("Deploying Core Scripts");

        CodeJar codeJar = quarkWalletFactory.codeJar();

        ethcall = Ethcall(codeJar.saveCode(vm.getDeployedCode(string.concat("out/", "Ethcall.sol/Ethcall.json"))));
        console.log("Ethcall Deployed:", address(ethcall));

        multicall =
            Multicall(codeJar.saveCode(vm.getDeployedCode(string.concat("out/", "Multicall.sol/Multicall.json"))));
        console.log("Multicall Deployed:", address(multicall));

        console.log("=============================================================");

        vm.stopBroadcast();
    }
}
