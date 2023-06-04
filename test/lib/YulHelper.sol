// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

contract YulHelper is Test {
    function get(string memory jsonFileName) public view returns (bytes memory) {
        return vm.getCode(string.concat("out/", jsonFileName));
    }

    function getDeployed(string memory jsonFileName) public view returns (bytes memory) {
        return vm.getDeployedCode(string.concat("out/", jsonFileName));
    }
}
