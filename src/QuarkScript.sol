// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

abstract contract QuarkScript {
    // Note: we really need to make sure this is here!
    function destruct() external {
        address relayer;
        address payable owner;
        assembly {
            owner := sload(0x3bb5ebf00f3b539fbe3d28370e5631dd2bb9520dffcea6daf564f94582db8111)
            relayer := sload(0x46ce4d9fc828e2af4f167362c7c43e310c76adc313cd8fe11e785726f972b4f6)
        }
        require(msg.sender == relayer);
        selfdestruct(owner);
    }

    function _exec(bytes calldata data) external returns (bytes memory) {
        bool callable;
        address relayer;
        assembly {
            callable := sload(0xabc5a6e5e5382747a356658e4038b20ca3422a2b81ab44fd6e725e9f1e4cf819)
            relayer := sload(0x46ce4d9fc828e2af4f167362c7c43e310c76adc313cd8fe11e785726f972b4f6)
        }
        require(callable || msg.sender == relayer);
        return run(data);
    }

    function run(bytes calldata data) internal virtual returns (bytes memory);
}
