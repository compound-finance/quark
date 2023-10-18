// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
contract CheckAddressEq {
    error CheckFailed();
    function check(bytes calldata data, bytes calldata checkData) external pure {
        address addrLeft = abi.decode(data, (address));
        address addrRight = abi.decode(checkData, (address));

        // Only revert if condition didn't meet
        if (addrLeft != addrRight) {
            revert CheckFailed();
        }
    }
}