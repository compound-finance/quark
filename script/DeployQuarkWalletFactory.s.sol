// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {QuarkWalletFactory} from "../src/QuarkWalletFactory.sol";

// Deploy with:
// $ set -a && source .env && ./script/deploy.sh --broadcast

// Required ENV vars:
// RPC_URL
// DEPLOYER_PK

// Optional ENV vars:
// ETHERSCAN_KEY

contract DeployQuarkWalletFactory is Script {
    QuarkWalletFactory quarkWalletFactory;

    function run() public {
        address deployer = vm.addr(vm.envUint("DEPLOYER_PK"));

        vm.startBroadcast(deployer);

        console.log("=============================================================");
        console.log("Deploying QuarkWalletFactory");

        quarkWalletFactory = new QuarkWalletFactory();

        console.log("QuarkWalletFactory Deployed:", address(quarkWalletFactory));
        console.log("=============================================================");

        vm.stopBroadcast();
    }
}
