// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract QuarkVm {
    event CallQuarkScript(bytes vmCode, bytes vmCalldata);

    struct VmCall {
        bytes vmCode;
        bytes vmCalldata;
    }

    function run(VmCall memory vmCall) external payable {
        require(false, "not implemented");
    }
}
