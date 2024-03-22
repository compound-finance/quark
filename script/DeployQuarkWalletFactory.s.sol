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
// $ set -a && source .env && ./script/deploy-quark.sh --broadcast

// Required ENV vars:
// RPC_URL
// DEPLOYER_PK
// CODE_JAR

// Optional ENV vars:
// ETHERSCAN_KEY

contract DeployQuarkWalletFactory is Script {
    CodeJar codeJar;
    QuarkWalletProxyFactory quarkWalletProxyFactory;
    BatchExecutor batchExecutor;
    Ethcall ethcall;
    Multicall multicall;
    QuarkFactory quarkFactory;

    function run() public {
        address deployer = vm.addr(vm.envUint("DEPLOYER_PK"));
        codeJar = CodeJar(vm.envAddress("CODE_JAR"));
        console.log("Code Jar Address: ", address(codeJar));

        vm.startBroadcast(deployer);

        console.log("=============================================================");

        console.log("Deploying Quark Factory");
        quarkFactory = new QuarkFactory(codeJar);
        console.log("Quark Factory Deployed:", address(quarkFactory));

        quarkFactory.deployQuarkContracts();

        console.log("Quark State Manager Deployed:", address(quarkFactory.quarkStateManager()));
        console.log("Quark Wallet Implementation Deployed:", address(quarkFactory.quarkWalletImpl()));
        console.log("Quark Wallet Proxy Factory Deployed:", address(quarkFactory.quarkWalletProxyFactory()));
        console.log("Batch Executor Deployed:", address(quarkFactory.batchExecutor()));

        console.log("Deploying Core Scripts");

        ethcall = Ethcall(payable(codeJar.saveCode(abi.encodePacked(type(Ethcall).creationCode))));
        console.log("Ethcall Deployed:", address(ethcall));

        multicall = Multicall(payable(codeJar.saveCode(abi.encodePacked(type(Multicall).creationCode))));
        console.log("Multicall Deployed:", address(multicall));

        console.log("=============================================================");

        vm.stopBroadcast();
    }
}
