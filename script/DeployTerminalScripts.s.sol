// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";

import {QuarkWalletProxyFactory} from "../quark-proxy/src/QuarkWalletProxyFactory.sol";

import {
    CometSupplyActions,
    CometWithdrawActions,
    UniswapSwapActions,
    TransferActions,
    CometClaimRewards,
    CometSupplyMultipleAssetsAndBorrow,
    CometRepayAndWithdrawMultipleAssets
} from "../legend-scripts/src/LegendScript.sol";

// Deploy with:
// $ set -a && source .env && ./script/deploy.sh --broadcast

// Required ENV vars:
// RPC_URL
// DEPLOYER_PK
// QUARK_WALLET_FACTORY_ADDRESS

// Optional ENV vars:
// ETHERSCAN_KEY

contract DeployTerminalScripts is Script {
    CometSupplyActions cometSupplyActions;
    CometWithdrawActions cometWithdrawActions;
    UniswapSwapActions uniswapSwapActions;
    TransferActions transferActions;
    CometClaimRewards cometClaimRewards;
    CometSupplyMultipleAssetsAndBorrow cometSupplyMultipleAssetsAndBorrow;
    CometRepayAndWithdrawMultipleAssets cometRepayAndWithdrawMultipleAssets;

    function run() public {
        address deployer = vm.addr(vm.envUint("DEPLOYER_PK"));
        QuarkWalletProxyFactory factory = QuarkWalletProxyFactory(vm.envAddress("QUARK_WALLET_FACTORY_ADDRESS"));
        CodeJar codeJar = QuarkWallet(payable(factory.walletImplementation())).codeJar();

        vm.startBroadcast(deployer);

        console.log("=============================================================");
        console.log("Deploying Terminal Scripts");

        cometSupplyActions = CometSupplyActions(
            codeJar.saveCode(vm.getDeployedCode(string.concat("out/", "LegendScript.sol/CometSupplyActions.json")))
        );
        console.log("CometSupplyActions Deployed:", address(cometSupplyActions));

        cometWithdrawActions = CometWithdrawActions(
            codeJar.saveCode(vm.getDeployedCode(string.concat("out/", "LegendScript.sol/CometWithdrawActions.json")))
        );
        console.log("CometWithdrawActions Deployed:", address(cometWithdrawActions));

        uniswapSwapActions = UniswapSwapActions(
            codeJar.saveCode(vm.getDeployedCode(string.concat("out/", "LegendScript.sol/UniswapSwapActions.json")))
        );
        console.log("UniswapSwapActions Deployed:", address(uniswapSwapActions));

        transferActions = TransferActions(
            codeJar.saveCode(vm.getDeployedCode(string.concat("out/", "LegendScript.sol/TransferActions.json")))
        );
        console.log("TransferActions Deployed:", address(transferActions));

        cometClaimRewards = CometClaimRewards(
            codeJar.saveCode(vm.getDeployedCode(string.concat("out/", "LegendScript.sol/CometClaimRewards.json")))
        );
        console.log("CometClaimRewards Deployed:", address(cometClaimRewards));

        cometSupplyMultipleAssetsAndBorrow = CometSupplyMultipleAssetsAndBorrow(
            codeJar.saveCode(
                vm.getDeployedCode(string.concat("out/", "LegendScript.sol/CometSupplyMultipleAssetsAndBorrow.json"))
            )
        );
        console.log("CometSupplyMultipleAssetsAndBorrow Deployed:", address(cometSupplyMultipleAssetsAndBorrow));

        cometRepayAndWithdrawMultipleAssets = CometRepayAndWithdrawMultipleAssets(
            codeJar.saveCode(
                vm.getDeployedCode(string.concat("out/", "LegendScript.sol/CometRepayAndWithdrawMultipleAssets.json"))
            )
        );
        console.log("CometRepayAndWithdrawMultipleAssets Deployed:", address(cometRepayAndWithdrawMultipleAssets));

        console.log("=============================================================");

        vm.stopBroadcast();
    }
}
