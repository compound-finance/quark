// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

/**
 * @title Quark Wallet interface
 * @notice An interface for interacting with Quark Wallets
 * @author Compound Labs, Inc.
 */
interface IQuarkWallet {
    /// @notice The structure of a signed operation to execute in the context of this wallet
    struct QuarkOperation {
        /// @notice Nonce identifier for the operation
        uint96 nonce;
        /// @notice The address of the transaction script to run
        address scriptAddress;
        /// @notice Creation codes Quark must ensure are deployed before executing this operation
        bytes[] scriptSources;
        /// @notice Encoded function selector + arguments to invoke on the script contract
        bytes scriptCalldata;
        /// @notice Expiration time for the signature corresponding to this operation
        uint256 expiry;
    }

    function executeQuarkOperation(QuarkOperation calldata op, uint8 v, bytes32 r, bytes32 s)
        external
        returns (bytes memory);
    function executeMultiQuarkOperation(
        QuarkOperation calldata op,
        bytes32[] memory opDigests,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (bytes memory);
    function executeScript(
        uint96 nonce,
        address scriptAddress,
        bytes calldata scriptCalldata,
        bytes[] calldata scriptSources
    ) external returns (bytes memory);
    function getDigestForQuarkOperation(QuarkOperation calldata op) external view returns (bytes32);
    function getDigestForMultiQuarkOperation(bytes32[] memory opDigests) external pure returns (bytes32);
    function getDigestForQuarkMessage(bytes memory message) external view returns (bytes32);
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4);
    function executeScriptWithNonceLock(address scriptAddress, bytes memory scriptCalldata)
        external
        returns (bytes memory);
}
