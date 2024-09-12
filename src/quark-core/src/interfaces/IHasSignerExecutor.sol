// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

/**
 * @title Has Signer and Executor interface
 * @notice A helper interface that represents a shell for a QuarkWallet providing an executor and signer
 * @author Compound Labs, Inc.
 */
interface IHasSignerExecutor {
    function signer() external view returns (address);
    function executor() external view returns (address);
}
