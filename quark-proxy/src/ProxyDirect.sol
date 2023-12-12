// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

contract ProxyDirect {
    /// @notice Address of the EOA signer or the EIP-1271 contract that verifies signed operations for this wallet
    address public immutable signer;

    /// @notice Address of the executor contract, if any, empowered to direct-execute unsigned operations for this wallet
    address public immutable executor;

    /// @notice Address of the QuarkWallet implementation contract
    address internal immutable walletImplementation;

    /**
     * @notice Construct a new QuarkWallet
     * @param implementation_ Address of QuarkWallet implementation contract
     * @param signer_ Address allowed to sign QuarkOperations for this wallet
     * @param executor_ Address allowed to directly execute Quark scripts for this wallet
     */
    constructor(address implementation_, address signer_, address executor_) {
        signer = signer_;
        executor = executor_;
        walletImplementation = implementation_;
    }

    /**
     * @notice Proxy calls to the underlying wallet implementation
     */
    fallback(bytes calldata /* data */) external payable returns (bytes memory) {
        address walletImplementation_ = walletImplementation;
        assembly {
            let calldataLen := calldatasize()
            calldatacopy(0, 0, calldataLen)
            let success := delegatecall(gas(), walletImplementation_, 0x00, calldataLen, 0x00, 0)
            let returnSize := returndatasize()
            returndatacopy(0, 0, returnSize)
            if success {
                return(0, returnSize)
            }

            revert(0, returnSize)
        }
    }

    receive() external payable {}
}
