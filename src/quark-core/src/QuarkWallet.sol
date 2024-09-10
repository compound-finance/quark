// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import {ECDSA} from "openzeppelin/utils/cryptography/ECDSA.sol";
import {IERC1271} from "openzeppelin/interfaces/IERC1271.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkNonceManager} from "quark-core/src/QuarkNonceManager.sol";
import {IHasSignerExecutor} from "quark-core/src/interfaces/IHasSignerExecutor.sol";

/**
 * @title Quark Wallet Metadata
 * @notice A library of metadata specific to this implementation of the Quark Wallet
 * @author Compound Labs, Inc.
 */
library QuarkWalletMetadata {
    /// @notice QuarkWallet contract name
    string internal constant NAME = "Quark Wallet";

    /// @notice QuarkWallet contract major version
    string internal constant VERSION = "1";

    /// @notice The EIP-712 typehash for authorizing an operation for this version of QuarkWallet
    bytes32 internal constant QUARK_OPERATION_TYPEHASH = keccak256(
        "QuarkOperation(bytes32 nonce,bool isReplayable,address scriptAddress,bytes[] scriptSources,bytes scriptCalldata,uint256 expiry)"
    );

    /// @notice The EIP-712 typehash for authorizing a MultiQuarkOperation for this version of QuarkWallet
    bytes32 internal constant MULTI_QUARK_OPERATION_TYPEHASH = keccak256("MultiQuarkOperation(bytes32[] opDigests)");

    /// @notice The EIP-712 typehash for authorizing an EIP-1271 signature for this version of QuarkWallet
    bytes32 internal constant QUARK_MSG_TYPEHASH = keccak256("QuarkMessage(bytes message)");

    /// @notice The EIP-712 domain typehash for this version of QuarkWallet
    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 domain typehash used for MultiQuarkOperations for this version of QuarkWallet
    bytes32 internal constant MULTI_QUARK_OPERATION_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version)");
}

/**
 * @title Quark Wallet base class
 * @notice A smart wallet that can run transaction scripts
 * @dev An implementor needs only to provide a public signer and executor: these could be constants, immutables, or address getters of any kind
 * @author Compound Labs, Inc.
 */
contract QuarkWallet is IERC1271 {
    error BadSignatory();
    error EmptyCode();
    error InvalidEIP1271Signature();
    error InvalidMultiQuarkOperation();
    error InvalidSignature();
    error NoActiveCallback();
    error SignatureExpired();
    error Unauthorized();

    /// @notice Enum specifying the method of execution for running a Quark script
    enum ExecutionType {
        Signature,
        Direct
    }

    /// @notice Event emitted when a Quark script is executed by this Quark wallet
    event ExecuteQuarkScript(
        address indexed executor,
        address indexed scriptAddress,
        bytes32 indexed nonce,
        bytes32 submissionToken,
        ExecutionType executionType
    );

    /// @notice Address of CodeJar contract used to deploy transaction script source code
    CodeJar public immutable codeJar;

    /// @notice Address of QuarkNonceManager contract that manages nonces for this quark wallet
    QuarkNonceManager public immutable nonceManager;

    /// @notice Name of contract
    string public constant NAME = QuarkWalletMetadata.NAME;

    /// @notice The major version of this contract
    string public constant VERSION = QuarkWalletMetadata.VERSION;

    /// @dev The EIP-712 domain typehash for this wallet
    bytes32 internal constant DOMAIN_TYPEHASH = QuarkWalletMetadata.DOMAIN_TYPEHASH;

    /// @dev The EIP-712 domain typehash used for MultiQuarkOperations for this wallet
    bytes32 internal constant MULTI_QUARK_OPERATION_DOMAIN_TYPEHASH =
        QuarkWalletMetadata.MULTI_QUARK_OPERATION_DOMAIN_TYPEHASH;

    /// @dev The EIP-712 typehash for authorizing an operation for this wallet
    bytes32 internal constant QUARK_OPERATION_TYPEHASH = QuarkWalletMetadata.QUARK_OPERATION_TYPEHASH;

    /// @dev The EIP-712 typehash for authorizing an operation that is part of a MultiQuarkOperation for this wallet
    bytes32 internal constant MULTI_QUARK_OPERATION_TYPEHASH = QuarkWalletMetadata.MULTI_QUARK_OPERATION_TYPEHASH;

    /// @dev The EIP-712 typehash for authorizing an EIP-1271 signature for this wallet
    bytes32 internal constant QUARK_MSG_TYPEHASH = QuarkWalletMetadata.QUARK_MSG_TYPEHASH;

    /// @dev The EIP-712 domain separator for a MultiQuarkOperation
    /// @dev Note: `chainId` and `verifyingContract` are left out so a single MultiQuarkOperation can be used to
    ///            execute operations on different chains and wallets.
    bytes32 internal constant MULTI_QUARK_OPERATION_DOMAIN_SEPARATOR = keccak256(
        abi.encode(
            QuarkWalletMetadata.MULTI_QUARK_OPERATION_DOMAIN_TYPEHASH,
            keccak256(bytes(QuarkWalletMetadata.NAME)),
            keccak256(bytes(QuarkWalletMetadata.VERSION))
        )
    );

    /// @notice Well-known storage slot for the currently executing script's callback address (if any)
    bytes32 public constant CALLBACK_SLOT = bytes32(uint256(keccak256("quark.v1.callback")) - 1);

    /// @notice Well-known storage slot for the currently executing script's address (if any)
    bytes32 public constant ACTIVE_SCRIPT_SLOT = bytes32(uint256(keccak256("quark.v1.active.script")) - 1);

    /// @notice Well-known --
    bytes32 public constant ACTIVE_NONCE_SLOT = bytes32(uint256(keccak256("quark.v1.active.nonce")) - 1);

    /// @notice Well-known --
    bytes32 public constant ACTIVE_SUBMISSION_TOKEN_SLOT =
        bytes32(uint256(keccak256("quark.v1.active.submissionToken")) - 1);

    /// @notice A nonce submission token that implies a Quark Operation is no longer replayable.
    bytes32 public constant EXHAUSTED_TOKEN = bytes32(type(uint256).max);

    /// @notice The magic value to return for valid ERC1271 signature
    bytes4 internal constant EIP_1271_MAGIC_VALUE = 0x1626ba7e;

    /// @notice The structure of a signed operation to execute in the context of this wallet
    struct QuarkOperation {
        /// @notice Nonce identifier for the operation
        bytes32 nonce;
        /// @notice Whether this script is replayable or not.
        bool isReplayable;
        /// @notice The address of the transaction script to run
        address scriptAddress;
        /// @notice Creation codes Quark must ensure are deployed before executing this operation
        bytes[] scriptSources;
        /// @notice Encoded function selector + arguments to invoke on the script contract
        bytes scriptCalldata;
        /// @notice Expiration time for the signature corresponding to this operation
        uint256 expiry;
    }

    /**
     * @notice Construct a new QuarkWalletImplementation
     * @param codeJar_ The CodeJar contract used to deploy scripts
     * @param nonceManager_ The QuarkNonceManager contract used to write/read nonces for this wallet
     */
    constructor(CodeJar codeJar_, QuarkNonceManager nonceManager_) {
        codeJar = codeJar_;
        nonceManager = nonceManager_;
    }

    /**
     * @notice Execute a QuarkOperation via signature
     * @dev Can only be called with signatures from the wallet's signer
     * @param op A QuarkOperation struct
     * @param v EIP-712 signature v value
     * @param r EIP-712 signature r value
     * @param s EIP-712 signature s value
     * @return Return value from the executed operation
     */
    function executeQuarkOperation(QuarkOperation calldata op, uint8 v, bytes32 r, bytes32 s)
        external
        returns (bytes memory)
    {
        return executeQuarkOperationWithSubmissionToken(op, getInitialSubmissionToken(op), v, r, s);
    }

    /**
     * @notice Executes a first play or a replay of a QuarkOperation via signature
     * @dev Can only be called with signatures from the wallet's signer
     * @param op A QuarkOperation struct
     * @param submissionToken A submission token. For replayable operations, initial value should be `submissionToken = op.nonce`, for non-replayable operations, `submissionToken = bytes32(type(uint256).max)`.
     * @param v EIP-712 signature v value
     * @param r EIP-712 signature r value
     * @param s EIP-712 signature s value
     * @return Return value from the executed operation
     */
    function executeQuarkOperationWithSubmissionToken(
        QuarkOperation calldata op,
        bytes32 submissionToken,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public returns (bytes memory) {
        bytes32 opDigest = getDigestForQuarkOperation(op);

        return verifySigAndExecuteQuarkOperation(op, submissionToken, opDigest, v, r, s);
    }

    /**
     * @notice Execute a QuarkOperation that is part of a MultiQuarkOperation via signature
     * @dev Can only be called with signatures from the wallet's signer
     * @param op A QuarkOperation struct
     * @param opDigests A list of EIP-712 digests for the operations in a MultiQuarkOperation
     * @param v EIP-712 signature v value
     * @param r EIP-712 signature r value
     * @param s EIP-712 signature s value
     * @return Return value from the executed operation
     */
    function executeMultiQuarkOperation(
        QuarkOperation calldata op,
        bytes32[] memory opDigests,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public returns (bytes memory) {
        return executeMultiQuarkOperationWithReplayToken(op, getInitialSubmissionToken(op), opDigests, v, r, s);
    }

    /**
     * @notice Executes a first play or a replay of a QuarkOperation that is part of a MultiQuarkOperation via signature
     * @dev Can only be called with signatures from the wallet's signer
     * @param op A QuarkOperation struct
     * @param replayToken A replay token. For replayables, initial value should be `replayToken = op.nonce`, for non-replayables, `replayToken = bytes32(type(uint256).max)`
     * @param opDigests A list of EIP-712 digests for the operations in a MultiQuarkOperation
     * @param v EIP-712 signature v value
     * @param r EIP-712 signature r value
     * @param s EIP-712 signature s value
     * @return Return value from the executed operation
     */
    function executeMultiQuarkOperationWithReplayToken(
        QuarkOperation calldata op,
        bytes32 replayToken,
        bytes32[] memory opDigests,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public returns (bytes memory) {
        bytes32 opDigest = getDigestForQuarkOperation(op);

        bool isValidOp = false;
        for (uint256 i = 0; i < opDigests.length; ++i) {
            if (opDigest == opDigests[i]) {
                isValidOp = true;
                break;
            }
        }
        if (!isValidOp) {
            revert InvalidMultiQuarkOperation();
        }
        bytes32 multiOpDigest = getDigestForMultiQuarkOperation(opDigests);

        return verifySigAndExecuteQuarkOperation(op, replayToken, multiOpDigest, v, r, s);
    }

    /**
     * @notice Verify a signature and execute a replayable QuarkOperation
     * @param op A QuarkOperation struct
     * @param submissionToken The submission token for the replayable quark operation for QuarkNonceManager. For the first submission, this is generally the `rootHash` of a chain.
     * @param digest A EIP-712 digest for either a QuarkOperation or MultiQuarkOperation to verify the signature against
     * @param v EIP-712 signature v value
     * @param r EIP-712 signature r value
     * @param s EIP-712 signature s value
     * @return Return value from the executed operation
     */
    function verifySigAndExecuteQuarkOperation(
        QuarkOperation calldata op,
        bytes32 submissionToken,
        bytes32 digest,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal returns (bytes memory) {
        if (block.timestamp >= op.expiry) {
            revert SignatureExpired();
        }

        // if the signature check does not revert, the signature is valid
        checkValidSignatureInternal(IHasSignerExecutor(address(this)).signer(), digest, v, r, s);

        // guarantee every script in scriptSources is deployed
        for (uint256 i = 0; i < op.scriptSources.length; ++i) {
            codeJar.saveCode(op.scriptSources[i]);
        }

        nonceManager.submit(op.nonce, op.isReplayable, submissionToken);

        emit ExecuteQuarkScript(msg.sender, op.scriptAddress, op.nonce, submissionToken, ExecutionType.Signature);

        return executeScriptInternal(op.scriptAddress, op.scriptCalldata, op.nonce, submissionToken);
    }

    /**
     * @notice Execute a transaction script directly
     * @dev Can only be called by the wallet's executor
     * @param nonce Nonce for the operation; must be unused
     * @param scriptAddress Address for the script to execute
     * @param scriptCalldata Encoded call to invoke on the script
     * @param scriptSources Creation codes Quark must ensure are deployed before executing the script
     * @return Return value from the executed operation
     */
    function executeScript(
        bytes32 nonce,
        address scriptAddress,
        bytes calldata scriptCalldata,
        bytes[] calldata scriptSources
    ) external returns (bytes memory) {
        // only allow the executor for the wallet to use unsigned execution
        if (msg.sender != IHasSignerExecutor(address(this)).executor()) {
            revert Unauthorized();
        }

        // guarantee every script in scriptSources is deployed
        for (uint256 i = 0; i < scriptSources.length; ++i) {
            codeJar.saveCode(scriptSources[i]);
        }

        nonceManager.submit(nonce, false, EXHAUSTED_TOKEN);

        emit ExecuteQuarkScript(msg.sender, scriptAddress, nonce, EXHAUSTED_TOKEN, ExecutionType.Direct);

        return executeScriptInternal(scriptAddress, scriptCalldata, nonce, EXHAUSTED_TOKEN);
    }

    /**
     * @dev Returns the domain separator for this Quark wallet
     * @return Domain separator
     */
    function getDomainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(NAME)), keccak256(bytes(VERSION)), block.chainid, address(this))
        );
    }

    /**
     * @dev Returns the EIP-712 digest for a QuarkOperation
     * @param op A QuarkOperation struct
     * @return EIP-712 digest
     */
    function getDigestForQuarkOperation(QuarkOperation calldata op) public view returns (bytes32) {
        bytes memory encodedScriptSources;
        for (uint256 i = 0; i < op.scriptSources.length; ++i) {
            encodedScriptSources = abi.encodePacked(encodedScriptSources, keccak256(op.scriptSources[i]));
        }

        bytes32 structHash = keccak256(
            abi.encode(
                QUARK_OPERATION_TYPEHASH,
                op.nonce,
                op.isReplayable,
                op.scriptAddress,
                keccak256(encodedScriptSources),
                keccak256(op.scriptCalldata),
                op.expiry
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", getDomainSeparator(), structHash));
    }

    /**
     * @dev Returns the EIP-712 digest for a MultiQuarkOperation
     * @param opDigests A list of EIP-712 digests for the operations in a MultiQuarkOperation
     * @return EIP-712 digest
     */
    function getDigestForMultiQuarkOperation(bytes32[] memory opDigests) public pure returns (bytes32) {
        bytes memory encodedOpDigests = abi.encodePacked(opDigests);
        bytes32 structHash = keccak256(abi.encode(MULTI_QUARK_OPERATION_TYPEHASH, keccak256(encodedOpDigests)));
        return keccak256(abi.encodePacked("\x19\x01", MULTI_QUARK_OPERATION_DOMAIN_SEPARATOR, structHash));
    }

    /**
     * @dev Returns the EIP-712 digest of a QuarkMessage that can be signed by `signer`
     * @param message Message that should be hashed
     * @return Message hash
     */
    function getDigestForQuarkMessage(bytes memory message) public view returns (bytes32) {
        bytes32 quarkMessageHash = keccak256(abi.encode(QUARK_MSG_TYPEHASH, keccak256(message)));
        return keccak256(abi.encodePacked("\x19\x01", getDomainSeparator(), quarkMessageHash));
    }

    /**
     * @notice Checks whether an EIP-1271 signature is valid
     * @dev If the QuarkWallet is owned by an EOA, isValidSignature confirms
     * that the signature comes from the signer; if the QuarkWallet is owned by
     * a smart contract, isValidSignature relays the `isValidSignature` to the
     * smart contract
     * @param hash Hash of the signed data
     * @param signature Signature byte array associated with data
     * @return The ERC-1271 "magic value" that indicates the signature is valid
     */
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4) {
        /*
         * Code taken directly from OpenZeppelin ECDSA.tryRecover; see:
         * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/HEAD/contracts/utils/cryptography/ECDSA.sol#L64-L68
         *
         * This is effectively an optimized variant of the Reference Implementation; see:
         * https://eips.ethereum.org/EIPS/eip-1271#reference-implementation
         */
        if (signature.length != 65) {
            revert InvalidSignature();
        }
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
        // Note: The following logic further encodes the provided `hash` with the wallet's domain
        // to prevent signature replayability for Quark wallets owned by the same `signer`
        bytes32 digest = getDigestForQuarkMessage(abi.encode(hash));
        // If the signature check does not revert, the signature is valid
        checkValidSignatureInternal(IHasSignerExecutor(address(this)).signer(), digest, v, r, s);
        return EIP_1271_MAGIC_VALUE;
    }

    /**
     * @dev If the QuarkWallet is owned by an EOA, isValidSignature confirms
     * that the signature comes from the signer; if the QuarkWallet is owned by
     * a smart contract, isValidSignature relays the `isValidSignature` check
     * to the smart contract; if the smart contract that owns the wallet has no
     * code, the signature will be treated as an EIP-712 signature and revert
     */
    function checkValidSignatureInternal(address signatory, bytes32 digest, uint8 v, bytes32 r, bytes32 s)
        internal
        view
    {
        if (signatory.code.length > 0) {
            bytes memory signature = abi.encodePacked(r, s, v);
            (bool success, bytes memory data) =
                signatory.staticcall(abi.encodeWithSelector(EIP_1271_MAGIC_VALUE, digest, signature));
            if (!success) {
                revert InvalidEIP1271Signature();
            }
            bytes4 returnValue = abi.decode(data, (bytes4));
            if (returnValue != EIP_1271_MAGIC_VALUE) {
                revert InvalidEIP1271Signature();
            }
        } else {
            (address recoveredSigner, ECDSA.RecoverError recoverError) = ECDSA.tryRecover(digest, v, r, s);
            if (recoverError != ECDSA.RecoverError.NoError) {
                revert InvalidSignature();
            }
            if (recoveredSigner != signatory) {
                revert BadSignatory();
            }
        }
    }

    /**
     * @notice Execute a script using the given calldata
     * @param scriptAddress Address of script to execute
     * @param scriptCalldata Encoded calldata for the call to execute on the scriptAddress
     * @param nonce The nonce of the quark operation for this execution
     * @param submissionToken The submission token for this quark execution
     * @return Result of executing the script, encoded as bytes
     */
    function executeScriptInternal(
        address scriptAddress,
        bytes memory scriptCalldata,
        bytes32 nonce,
        bytes32 submissionToken
    ) internal returns (bytes memory) {
        if (scriptAddress.code.length == 0) {
            revert EmptyCode();
        }

        bool success;
        uint256 returnSize;
        uint256 scriptCalldataLen = scriptCalldata.length;
        bytes32 activeScriptSlot = ACTIVE_SCRIPT_SLOT;
        bytes32 activeNonceSlot = ACTIVE_NONCE_SLOT;
        bytes32 activeSubmissionTokenSlot = ACTIVE_SUBMISSION_TOKEN_SLOT;
        assembly {
            // TODO: TSTORE the callback slot to 0

            // Store the active script
            // TODO: Move to TSTORE after updating Solidity version to >=0.8.24
            sstore(activeScriptSlot, scriptAddress)

            // Store the active nonce
            // TODO: Move to TSTORE after updating Solidity version to >=0.8.24
            sstore(activeNonceSlot, nonce)

            // Store the active submission token
            // TODO: Move to TSTORE after updating Solidity version to >=0.8.24
            sstore(activeSubmissionTokenSlot, submissionToken)

            // Note: CALLCODE is used to set the QuarkWallet as the `msg.sender`
            success :=
                callcode(gas(), scriptAddress, /* value */ 0, add(scriptCalldata, 0x20), scriptCalldataLen, 0x0, 0)
            returnSize := returndatasize()

            // TODO: Move to TSTORE after updating Solidity version to >=0.8.24
            sstore(activeScriptSlot, 0)

            // TODO: Move to TSTORE after updating Solidity version to >=0.8.24
            sstore(activeNonceSlot, 0)

            // TODO: Move to TSTORE after updating Solidity version to >=0.8.24
            sstore(activeSubmissionTokenSlot, 0)
        }

        bytes memory returnData = new bytes(returnSize);
        assembly {
            returndatacopy(add(returnData, 0x20), 0x00, returnSize)
        }

        if (!success) {
            assembly {
                revert(add(returnData, 0x20), returnSize)
            }
        }

        return returnData;
    }

    /**
     * @notice Fallback function specifically used for scripts that have enabled callbacks
     * @dev Reverts if callback is not enabled by the script
     */
    fallback(bytes calldata data) external payable returns (bytes memory) {
        bytes32 callbackSlot = CALLBACK_SLOT;
        address callback;
        assembly {
            // TODO: Move to TLOAD after updating Solidity version to >=0.8.24
            callback := sload(callbackSlot)
        }
        if (callback != address(0)) {
            (bool success, bytes memory result) = callback.delegatecall(data);
            if (!success) {
                assembly {
                    let size := mload(result)
                    revert(add(result, 0x20), size)
                }
            }
            return result;
        } else {
            revert NoActiveCallback();
        }
    }

    /// @notice Fallback for receiving native token
    receive() external payable {}

    /// @dev Returns the expected initial submission token for an operation, which is either `op.nonce` for a replayable operation, or `bytes32(type(uint256).max)` (the "exhausted" token) for a non-replayable operation.
    function getInitialSubmissionToken(QuarkOperation memory op) internal pure returns (bytes32) {
        return op.isReplayable ? op.nonce : EXHAUSTED_TOKEN;
    }
}
