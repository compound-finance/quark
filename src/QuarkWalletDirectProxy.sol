// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "openzeppelin/proxy/Proxy.sol";
import {CodeJar} from "./CodeJar.sol";
import {QuarkStateManager} from "./QuarkStateManager.sol";

contract QuarkWalletDirectProxy is Proxy {
    address public immutable impl;

    address public immutable initializer;

    constructor(address signer, address executor, address impl_, address initializer_) {
        impl = impl_;
        initializer = initializer_;
    }

    function initialize(address signer, address executor, QuarkStateManager stateManager_) public {
        require(msg.sender == initializer, "QuarkWalletDirectProxy: not initializer");
        stateManager_.writeImmutable(bytes32("signer"), bytes32(uint256(uint160(signer))));
        stateManager_.writeImmutable(bytes32("executor"), bytes32(uint256(uint160(executor))));
    }

    function _implementation() internal view virtual override returns (address) {
        return impl;
    }
}
