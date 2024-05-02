// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import {QuarkScript} from "quark-core/src/QuarkScript.sol";

/**
 * @title Recurrent Core Script
 * @notice Core transaction script that can be used to call a function every so often
 * @author Compound Labs, Inc.
 */
contract Recurrent is QuarkScript {
    error InvalidCallContext();
    error TooFrequent(uint256 lastExecution);
    error Premature();
    error Expired();

    /// @notice This contract's address
    address internal immutable scriptAddress;

    /**
     * @notice Constructor
     */
    constructor() {
        scriptAddress = address(this);
    }

    /**
     * @notice Execute a single call
     * @dev Note: Does not use a reentrancy guard, so make sure to only call into trusted contracts
     * @param callContract Contract to call
     * @param callData Encoded calldata for call
     * @param interval Interval for the call in seconds (i.e. every X seconds)
     * @param notBefore Do not run this script before this time.
     * @param notAfter Do not run this script after this time.
     * @return Return data from call
     */
    function run(address callContract, bytes calldata callData, uint256 interval, uint256 notBefore, uint256 notAfter) external returns (bytes memory) {
        if (address(this) == scriptAddress) {
            revert InvalidCallContext();
        }

        // Note: this starts out as zero, as in
        uint256 lastExecution = readU256("lastExecution");
        if (block.timestamp < lastExecution + interval) revert TooFrequent(lastExecution);
        if (block.timestamp < notBefore) revert Premature();
        if (block.timestamp > notAfter) revert Expired();
        writeU256("lastExecution", block.timestamp);

        (bool success, bytes memory returnData) = callContract.delegatecall(callData);
        if (!success) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }

        allowReplay();

        return returnData;
    }
}
