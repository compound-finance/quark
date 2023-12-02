// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

contract ProxyDirect {
    /// @notice Address of the EOA signer or the EIP-1271 contract that verifies signed operations for this wallet
    address public immutable signer;

    /// @notice Address of the executor contract, if any, empowered to direct-execute unsigned operations for this wallet
    address public immutable executor;

    /// @notice Address of the quark wallet implementation code
    address immutable walletImplementation;

    /**
     * @notice Construct a new QuarkWallet
     * @param signer_ The address that is allowed to sign QuarkOperations for this wallet
     * @param executor_ The address that is allowed to directly execute Quark scripts for this wallet
     */
    constructor(address implementation_, address signer_, address executor_) {
        signer = signer_;
        executor = executor_;
        walletImplementation = implementation_;
    }

    /**
     * @notice Proxy calls into the underlying wallet implementation
     */
    fallback(bytes calldata /* data */) external payable returns (bytes memory) {
        address walletImplementation_ = walletImplementation;
        assembly {
            let calldataLen := calldatasize()
            calldatacopy(0, 0, calldataLen)
            let succ := delegatecall(gas(), walletImplementation_, 0x00, calldataLen, 0x00, 0x00)
            let retSz := returndatasize()
            returndatacopy(0, 0, retSz)
            if succ {
                return(0, retSz)
            }

            revert(0, retSz)
        }
    }
}
