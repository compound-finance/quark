// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import {ECDSA} from "openzeppelin/utils/cryptography/ECDSA.sol";
import {IERC1271} from "openzeppelin/interfaces/IERC1271.sol";

/**
 * @title EIP-1271 Multi Signer
 * @notice Contract which requires M of N immutable signatures for EIP-1271 verification
 * @author Legend Labs, Inc.
 */
contract EIP1271MultiSigner is IERC1271 {
    error BadSignatory();
    error IncorrectSignatureCount();
    error InvalidRequiredSigners();
    error InvalidSignature();
    error MisplacedSigner();
    error UninitializedSigner();

    /// @notice The magic value to return for valid ERC1271 signature
    bytes4 internal constant EIP_1271_MAGIC_VALUE = 0x1626ba7e;

    /// @notice The number of signatures required
    uint256 public immutable requiredSignatures;

    /// @notice The address of signer #0, or address(0) if unset.
    address public immutable signer0;

    /// @notice The address of signer #1, or address(0) if unset.
    address public immutable signer1;

    /// @notice The address of signer #2, or address(0) if unset.
    address public immutable signer2;

    /// @notice The address of signer #3, or address(0) if unset.
    address public immutable signer3;

    /// @notice The address of signer #4, or address(0) if unset.
    address public immutable signer4;

    /// @notice The address of signer #5, or address(0) if unset.
    address public immutable signer5;

    /// @notice The address of signer #6, or address(0) if unset.
    address public immutable signer6;

    /// @notice The address of signer #7, or address(0) if unset.
    address public immutable signer7;

    /// @notice The address of signer #8, or address(0) if unset.
    address public immutable signer8;

    /// @notice The address of signer #9, or address(0) if unset.
    address public immutable signer9;

    /**
     * @notice Construct a new EIP1271MultiSigner
     * @dev Signers must be passed in in sort order (lowest address first).
     * @param requiredSignatures_ The required number of signers for a signature to be valid.
     * @param signer0_ The address of signer #0, or address(0) if unset.
     * @param signer1_ The address of signer #1, or address(0) if unset.
     * @param signer2_ The address of signer #2, or address(0) if unset.
     * @param signer3_ The address of signer #3, or address(0) if unset.
     * @param signer4_ The address of signer #4, or address(0) if unset.
     * @param signer5_ The address of signer #5, or address(0) if unset.
     * @param signer6_ The address of signer #6, or address(0) if unset.
     * @param signer7_ The address of signer #7, or address(0) if unset.
     * @param signer8_ The address of signer #8, or address(0) if unset.
     * @param signer9_ The address of signer #9, or address(0) if unset.
     */
    constructor(
        uint256 requiredSignatures_,
        address signer0_,
        address signer1_,
        address signer2_,
        address signer3_,
        address signer4_,
        address signer5_,
        address signer6_,
        address signer7_,
        address signer8_,
        address signer9_
    ) {
        requiredSignatures = requiredSignatures_;
        signer0 = signer0_;
        signer1 = signer1_;
        signer2 = signer2_;
        signer3 = signer3_;
        signer4 = signer4_;
        signer5 = signer5_;
        signer6 = signer6_;
        signer7 = signer7_;
        signer8 = signer8_;
        signer9 = signer9_;

        require(signer1_ == address(0) || signer1_ > signer0_, MisplacedSigner());
        require(signer2_ == address(0) || signer2_ > signer1_, MisplacedSigner());
        require(signer3_ == address(0) || signer3_ > signer2_, MisplacedSigner());
        require(signer4_ == address(0) || signer4_ > signer3_, MisplacedSigner());
        require(signer5_ == address(0) || signer5_ > signer4_, MisplacedSigner());
        require(signer6_ == address(0) || signer6_ > signer5_, MisplacedSigner());
        require(signer7_ == address(0) || signer7_ > signer6_, MisplacedSigner());
        require(signer8_ == address(0) || signer8_ > signer7_, MisplacedSigner());
        require(signer9_ == address(0) || signer9_ > signer8_, MisplacedSigner());

        require(requiredSignatures > 0, InvalidRequiredSigners());
        require(requiredSignatures <= 10, InvalidRequiredSigners());
        // if signer[X] == nil, then requiredSignatures must be <= X
        require(signer0_ != address(0) || requiredSignatures <= 0, InvalidRequiredSigners());
        require(signer1_ != address(0) || requiredSignatures <= 1, InvalidRequiredSigners());
        require(signer2_ != address(0) || requiredSignatures <= 2, InvalidRequiredSigners());
        require(signer3_ != address(0) || requiredSignatures <= 3, InvalidRequiredSigners());
        require(signer4_ != address(0) || requiredSignatures <= 4, InvalidRequiredSigners());
        require(signer5_ != address(0) || requiredSignatures <= 5, InvalidRequiredSigners());
        require(signer6_ != address(0) || requiredSignatures <= 6, InvalidRequiredSigners());
        require(signer7_ != address(0) || requiredSignatures <= 7, InvalidRequiredSigners());
        require(signer8_ != address(0) || requiredSignatures <= 8, InvalidRequiredSigners());
        require(signer9_ != address(0) || requiredSignatures <= 9, InvalidRequiredSigners());
    }

    /**
     * @notice Verifies a signature is valid for the given digest, checking a threshold of signatures.
     * @dev Signatures must be sorted *by signer* monotonically.
     * @param digest The digest of the data to verify the signature for.
     * @param signatureEncoded The list of signatures ABI-encoded as a `bytes[]`.
     * @return Return `EIP_1271_MAGIC_VALUE` if valid, otherwise reverts.
     */
    function isValidSignature(bytes32 digest, bytes calldata signatureEncoded) external view returns (bytes4) {
        bytes[] memory signatures = abi.decode(signatureEncoded, (bytes[]));

        require(signatures.length == requiredSignatures, IncorrectSignatureCount());

        address lastSigner = address(0);

        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory signature = signatures[i];

            (address recoveredSigner, ECDSA.RecoverError recoverError) = ECDSA.tryRecover(digest, signature);
            require(recoverError == ECDSA.RecoverError.NoError, InvalidSignature());
            require(isValidSigner(recoveredSigner), BadSignatory());

            // Require signers are sorted to prevent repeats
            require(recoveredSigner > lastSigner, MisplacedSigner());

            lastSigner = recoveredSigner;
        }

        return EIP_1271_MAGIC_VALUE;
    }

    // Checks the signature is one of the set signers.
    function isValidSigner(address signer) internal view returns (bool) {
        require(signer != address(0), UninitializedSigner());

        return signer == signer0 || signer == signer1 || signer == signer2 || signer == signer3 || signer == signer4
            || signer == signer5 || signer == signer6 || signer == signer7 || signer == signer8 || signer == signer9;
    }
}
