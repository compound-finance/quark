// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

/**
 * @title Has Signer Executor
 * @notice A helper interface that represents a shell for a QuarkWallet providing an executor and signer
 * @author Compound Labs, Inc.
 */
interface HasSignerExecutor {
    function signer() external view returns (address);
    function executor() external view returns (address);
}
