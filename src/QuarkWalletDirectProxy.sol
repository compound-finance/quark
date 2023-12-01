// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {QuarkStateManager} from "./QuarkStateManager.sol";

contract QuarkWalletDirectProxy {
    error NotInitializer();

    bytes32 internal constant SIGNER_KEY = keccak256("signer.v1.quark");

    bytes32 internal constant EXECUTOR_KEY = keccak256("executor.v1.quark");

    address public immutable impl;
    address public immutable initializer;

    constructor(address impl_, address initializer_) {
        impl = impl_;
        initializer = initializer_;
    }

    function initialize(address signer, address executor, QuarkStateManager stateManager_) public {
        if (msg.sender != initializer) {
            revert NotInitializer();
        }
        stateManager_.writeImmutable(SIGNER_KEY, bytes32(uint256(uint160(signer))));
        stateManager_.writeImmutable(EXECUTOR_KEY, bytes32(uint256(uint160(executor))));
    }

    fallback() external payable {
        address implementation = impl;
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}
