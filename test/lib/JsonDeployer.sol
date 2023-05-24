// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

contract JsonDeployer is Test {
    ///@notice Deploys json object
    ///@param jsonFileName - Artifact filename of the Yul contract. For example, the file name for "Example.yul/Object" is "Example.yul/Object.json"
    ///@return deployedAddress - The address that the contract was deployed to
    function deploy(string memory jsonFileName) public returns (address) {
        bytes memory bytecode = vm.getCode(string.concat("out/", jsonFileName));

        ///@notice deploy the bytecode with the create instruction
        address deployedAddress;
        assembly {
            deployedAddress := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        ///@notice check that the deployment was successful
        require(
            deployedAddress != address(0),
            "could not deploy contract"
        );

        ///@notice return the address that the contract was deployed to
        return deployedAddress;
    }
}
