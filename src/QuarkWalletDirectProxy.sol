// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "openzeppelin/proxy/Proxy.sol";
import {CodeJar} from "./CodeJar.sol";
import {QuarkStateManager} from "./QuarkStateManager.sol";

contract QuarkWalletDirectProxy is Proxy {
    /// @notice Address of the EOA signer or the EIP-1271 contract that verifies signed operations for this wallet
    address public signer;

    /// @notice Address of the executor contract, if any, empowered to direct-execute unsigned operations for this wallet
    address public executor;

    /// @notice Address of CodeJar contract used to deploy transaction script source code
    CodeJar public codeJar;

    /// @notice Address of QuarkStateManager contract that manages nonces and nonce-namespaced transaction script storage
    QuarkStateManager public stateManager;

    address public impl;

    constructor(address impl_, address signer_, address executor_, CodeJar codeJar_, QuarkStateManager stateManager_) {
        impl = impl_;
        signer = signer_;
        executor = executor_;
        codeJar = codeJar_;
        stateManager = stateManager_;
    }

    function _implementation() internal view virtual override returns (address) {
        return impl;
    }
}
