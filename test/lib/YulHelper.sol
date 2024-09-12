// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import "forge-std/Test.sol";

contract YulHelper is Test {
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
        require(deployedAddress != address(0), "could not deploy contract");

        ///@notice return the address that the contract was deployed to
        return deployedAddress;
    }

    function getCode(string memory jsonFileName) public view returns (bytes memory) {
        return vm.getCode(string.concat("out/", jsonFileName));
    }

    function getDeployed(string memory jsonFileName) public view returns (bytes memory) {
        return vm.getDeployedCode(string.concat("out/", jsonFileName));
    }

    /// EVM opcodes to simply return the code as a very simple `initCode` / "constructor"
    function stub(bytes memory code) public pure returns (bytes memory) {
        uint32 codeLen = uint32(code.length);
        return abi.encodePacked(hex"63", codeLen, hex"80600e6000396000f3", code);
    }
}
