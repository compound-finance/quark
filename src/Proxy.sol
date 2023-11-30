// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {CodeJar} from "./CodeJar.sol";
import {QuarkStateManager} from "./QuarkStateManager.sol";

contract Proxy {
    /// @notice Address of the EOA signer or the EIP-1271 contract that verifies signed operations for this wallet
    address public immutable signer;

    /// @notice Address of the executor contract, if any, empowered to direct-execute unsigned operations for this wallet
    address public immutable executor;

    /// @notice Address of CodeJar contract used to deploy transaction script source code
    CodeJar public immutable codeJar;

    /// @notice Address of QuarkStateManager contract that manages nonces and nonce-namespaced transaction script storage
    QuarkStateManager public immutable stateManager;

    /// @notice Address of the quark wallet implementation code
    address public immutable walletImplementation;

    /**
     * @notice Construct a new QuarkWallet
     * @param signer_ The address that is allowed to sign QuarkOperations for this wallet
     * @param executor_ The address that is allowed to directly execute Quark scripts for this wallet
     * @param codeJar_ The CodeJar contract used to deploy scripts
     * @param stateManager_ The QuarkStateManager contract used to write/read nonces and storage for this wallet
     */
    constructor(address implementation_, address signer_, address executor_, CodeJar codeJar_, QuarkStateManager stateManager_) {
        signer = signer_;
        executor = executor_;
        codeJar = codeJar_;
        stateManager = stateManager_;
        walletImplementation = implementation_;
    }

    /**
     * @notice Proxy calls into the underlying wallet implementation
     */
    fallback(bytes calldata data) external payable returns (bytes memory) {
        (bool success, bytes memory result) = walletImplementation.delegatecall(data);
        if (!success) {
            assembly {
                revert(add(result, 0x20), mload(result))
            }
        }
        return result;
    }
}
