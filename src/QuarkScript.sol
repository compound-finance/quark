// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Relayer.sol";

abstract contract QuarkScript is Quark {
    function isQuarkScript() external pure returns (bytes32) {
        return 0x390752087e6ef3cd5b0a0dede313512f6e47c12ea2c3b1972f19911725227c3e; // keccak("org.quark.isQuarkScript")
    }

    function relayer() internal view returns (Relayer) {
        Relayer relayer_;
        assembly {
            codecopy(0, sub(codesize(), 0x40), 0x40)
            let owner := mload(0x20)
        }
        return relayer_;
    }

    // Note: we really need to make sure this is here!
    function destruct() external {
        address relayer_;
        address payable owner;
        assembly {
            owner := sload(0x3bb5ebf00f3b539fbe3d28370e5631dd2bb9520dffcea6daf564f94582db8111)
            relayer_ := sload(0x46ce4d9fc828e2af4f167362c7c43e310c76adc313cd8fe11e785726f972b4f6)
        }
        require(msg.sender == relayer_);
        selfdestruct(owner);
    }

    function _exec(bytes calldata data) external returns (bytes memory) {
        bool callable;
        address relayer_;
        assembly {
            callable := sload(0xabc5a6e5e5382747a356658e4038b20ca3422a2b81ab44fd6e725e9f1e4cf819)
            relayer_ := sload(0x46ce4d9fc828e2af4f167362c7c43e310c76adc313cd8fe11e785726f972b4f6)
        }
        require(callable || msg.sender == relayer_);
        return run(data);
    }

    function run(bytes calldata data) internal virtual returns (bytes memory);
}
