// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {CodeJar} from "codejar/src/CodeJar.sol";

// Deploy with:
// $ set -a && source .env && ./script/deploy.sh --broadcast

// Required ENV vars:
// RPC_URL
// DEPLOYER_PK
// CODE_JAR
// CONTRACT

// Optional ENV vars:
// ETHERSCAN_KEY

contract CodeJarDeployer is Script {
    address constant DEFAULT_CODE_JAR = address(0xcA85333B65E86d114e2bd5b4aE23Fe6E6a3Ae8e3);

    function deploy(bytes memory contractCode, bytes memory constructorArgs, uint256 deployerPk) internal returns (address) {
        return deployWithOpts(contractCode, constructorArgs, deployerPk, address(0), false);
    }

    function deployDryRun(bytes memory contractCode, bytes memory constructorArgs, uint256 deployerPk) internal returns (address) {
        return deployWithOpts(contractCode, constructorArgs, deployerPk, address(0), true);
    }

    function deployWithOpts(bytes memory contractCode, bytes memory constructorArgs, uint256 deployerPk, address codeJarAddr, bool dryRun) internal returns (address) {
        CodeJar codeJar;
        if (codeJarAddr == address(0)) {
            codeJar = CodeJar(DEFAULT_CODE_JAR);
        } else {
            codeJar = CodeJar(codeJarAddr);
        }

        address initCodeAddr = codeJar.saveCode(abi.encodePacked(contractCode, constructorArgs));

        console.log("Locally deployed constructor to %a", initCodeAddr);

        bool success;
        uint256 retSize;

        assembly {
            success := call(gas(), initCodeAddr, 0, 0, 0, 0, 0)
            retSize := returndatasize()
        }
        bytes memory deployedCode = new bytes(retSize);
        assembly {
            returndatacopy(add(deployedCode, 0x20), 0x00, retSize)
        }

        if (!success) {
            assembly {
                revert(add(deployedCode, 0x20), retSize)
            }
        }

        // TODO: Consider metadata and verification
        bytes memory deployedCodeWithMetadata = abi.encodePacked(deployedCode, hex"");

        console.logBytes(deployedCodeWithMetadata);

        require(
            !codeJar.codeExists(deployedCodeWithMetadata),
            "Deployed code already exists-- select custom metadata to redeploy");

        if (!dryRun) {
            vm.broadcast(deployerPk);
        }
        return codeJar.saveCode(deployedCodeWithMetadata);
    }
}

contract DeployWithCodeJar is CodeJarDeployer {
    function run() public {
        bool dryRun = vm.envBool("DRY_RUN");

        uint256 deployerPk;
        address deployer = address(0);
        if (!dryRun) {
            deployerPk = vm.envUint("DEPLOYER_PK");
            deployer = vm.addr(deployerPk);
        }
        address codeJarAddr = vm.envAddress("CODE_JAR");

        string memory contractPath = vm.envString("CONTRACT");
        string memory metadata = vm.envString("METADATA");
        bytes memory constructorArgs = vm.envBytes("CONSTRUCTOR_ARGS");
        if (dryRun) {
            console.log("======================= [ Dry Run ] =========================");
        } else {
            console.log("=============================================================");
        }
        console.log("Deploying %s via CodeJar at %s with metadata %s", contractPath, contractPath, metadata);
        console.log("deployer=%s", deployer);
        console.logBytes(constructorArgs);

        bytes memory contractCode = vm.getCode(contractPath);

        address deployed = deployWithOpts(contractCode, constructorArgs, deployerPk, codeJarAddr, dryRun);
        console.log("Successfully deployed contract to %a", deployed);
    }
}