// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

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

    /// @notice Storage location at which to cache this contract's address
    bytes32 internal constant CONTRACT_ADDRESS_SLOT = keccak256("quark.scripts.multicall.address.v1");

    /// @notice Initialize by storing the contract address
    function initialize() external {
        bytes32 slot = CONTRACT_ADDRESS_SLOT;
        assembly ("memory-safe") {
            sstore(slot, address())
        }
    }

    /**
     * @notice Execute multiple delegatecalls to contracts in a single transaction
     * @param callContracts Array of contracts to call
     * @param callDatas Array of encoded calldata for each call
     * @return Array of return data from each call
     */
    function run(address[] calldata callContracts, bytes[] calldata callDatas) external returns (bytes[] memory) {
        bytes32 slot = CONTRACT_ADDRESS_SLOT;
        address thisAddress;
        assembly ("memory-safe") {
            thisAddress := sload(slot)
        }

        if (address(this) == thisAddress) {
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
