// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "openzeppelin/proxy/Proxy.sol";
import {CodeJar} from "./CodeJar.sol";
import {QuarkStateManager} from "./QuarkStateManager.sol";

contract QuarkWalletDirectProxy is Proxy {
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

    function _implementation() internal view virtual override returns (address) {
        return impl;
    }
}
