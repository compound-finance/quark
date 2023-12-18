// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

/**
 * @title Multicall Core Script
 * @notice Core transaction script that can be used to bundle multiple delegatecalls into a single operation
 * @author Compound Labs, Inc.
 */
contract Multicall {
    error AlreadyInitialized();
    error InvalidCallContext();
    error InvalidInput();
    error MulticallError(uint256 callIndex, address callContract, bytes err);

    /// @notice Flag to indicate if this contract has already been initialized
    bool internal initialized;

    /// @notice Storage location at which to cache this contract's address
    bytes32 internal constant MULTICALL_ADDRESS_SLOT = keccak256("quark.scripts.multicall.v1");

    /// @notice Initialize storage for contract
    function initialize() external {
        if (initialized == true) {
            revert AlreadyInitialized();
        }

        bytes32 slot = MULTICALL_ADDRESS_SLOT;
        assembly ("memory-safe") {
            sstore(slot, address())
        }
        initialized = true;
    }

    /**
     * @notice Execute multiple delegatecalls to contracts in a single transaction
     * @param callContracts Array of contracts to call
     * @param callDatas Array of encoded calldata for each call
     * @return Array of return data from each call
     */
    function run(address[] calldata callContracts, bytes[] calldata callDatas) external returns (bytes[] memory) {
        bytes32 slot = MULTICALL_ADDRESS_SLOT;
        address multicallAddress;
        assembly ("memory-safe") {
            multicallAddress := sload(slot)
        }

        if (address(this) == multicallAddress) {
            revert InvalidCallContext();
        }
        if (callContracts.length != callDatas.length) {
            revert InvalidInput();
        }

        bytes[] memory returnDatas = new bytes[](callContracts.length);
        for (uint256 i = 0; i < callContracts.length;) {
            (bool success, bytes memory returnData) = callContracts[i].delegatecall(callDatas[i]);
            if (!success) {
                revert MulticallError(i, callContracts[i], returnData);
            }
            returnDatas[i] = returnData;

            unchecked {
                ++i;
            }
        }

        return returnDatas;
    }
}
