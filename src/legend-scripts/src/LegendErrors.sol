// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

/**
 * @title Legend errors library
 * @notice Defines the custom errors that are returned by different Legend scripts
 * @author Compound Labs, Inc.
 */
library LegendErrors {
    error InvalidInput();
    error TransferFailed(bytes data);
    error ApproveAndSwapFailed(bytes data);
    error TooMuchSlippage();
}
