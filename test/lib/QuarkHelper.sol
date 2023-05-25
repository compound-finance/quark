// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

contract QuarkHelper is Test {
    function getExample(string memory exampleName) public returns (bytes memory) {
        string[] memory inputs = new string[](3);
        inputs[0] = "node";
        inputs[1] = "script/quark-trx.mjs";
        inputs[2] = exampleName;

        return vm.ffi(inputs);
    }
}
