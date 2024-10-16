// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

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

    /// @notice Well-known transient storage slot for the currently executing script's callback address (if any)
    bytes32 internal constant CALLBACK_SLOT = bytes32(uint256(keccak256("quark.v1.callback")) - 1);

    /// @notice Well-known transient storage slot for the currently executing script's address (if any)
    bytes32 internal constant ACTIVE_SCRIPT_SLOT = bytes32(uint256(keccak256("quark.v1.active.script")) - 1);

    /// @notice Well-known transient storage slot for the nonce of the script that's currently executing.
    bytes32 internal constant ACTIVE_NONCE_SLOT = bytes32(uint256(keccak256("quark.v1.active.nonce")) - 1);

    /// @notice Well-known transient storage slot for the submission token of the script that's currently executing.
    bytes32 internal constant ACTIVE_SUBMISSION_TOKEN_SLOT =
        bytes32(uint256(keccak256("quark.v1.active.submissionToken")) - 1);
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
    error UnauthorizedNestedOperation();

    /// @notice Enum specifying the method of execution for running a Quark script
    enum ExecutionType {
        Signature,
        Direct
    }

    /// @notice Event emitted when a Quark script is executed by this Quark wallet
    event QuarkExecution(
        address indexed executor,
        address indexed scriptAddress,
        bytes32 indexed nonce,
        bytes32 submissionToken,
        bool isReplayable,
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

    /// @notice Well-known transient storage slot for the currently executing script's callback address (if any)
    bytes32 public constant CALLBACK_SLOT = QuarkWalletMetadata.CALLBACK_SLOT;

    /// @notice Well-known transient storage slot for the currently executing script's address (if any)
    bytes32 public constant ACTIVE_SCRIPT_SLOT = QuarkWalletMetadata.ACTIVE_SCRIPT_SLOT;

    /// @notice Well-known transient storage slot for the nonce of the script that's currently executing.
    bytes32 public constant ACTIVE_NONCE_SLOT = QuarkWalletMetadata.ACTIVE_NONCE_SLOT;

    /// @notice Well-known transient storage slot for the submission token of the script that's currently executing.
    bytes32 public constant ACTIVE_SUBMISSION_TOKEN_SLOT = QuarkWalletMetadata.ACTIVE_SUBMISSION_TOKEN_SLOT;

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
     * @param signature A digital signature, e.g. EIP-712
     * @return Return value from the executed operation
     */
    function executeQuarkOperation(QuarkOperation calldata op, bytes calldata signature)
        external
        returns (bytes memory)
    {
        return executeQuarkOperationWithSubmissionToken(op, op.nonce, signature);
    }

    /**
     * @notice Executes a first play or a replay of a QuarkOperation via signature
     * @dev Can only be called with signatures from the wallet's signer
     * @param op A QuarkOperation struct
     * @param submissionToken The submission token for the replayable quark operation for QuarkNonceManager. This is initially the `op.nonce`, and for replayable operations, it is the next token in the nonce chain.
     * @param signature A digital signature, e.g. EIP-712
     * @return Return value from the executed operation
     */
    function executeQuarkOperationWithSubmissionToken(
        QuarkOperation calldata op,
        bytes32 submissionToken,
        bytes calldata signature
    ) public returns (bytes memory) {
        bytes32 opDigest = getDigestForQuarkOperation(op);

        return verifySigAndExecuteQuarkOperation(op, submissionToken, opDigest, signature);
    }

    /**
     * @notice Execute a QuarkOperation that is part of a MultiQuarkOperation via signature
     * @dev Can only be called with signatures from the wallet's signer
     * @param op A QuarkOperation struct
     * @param opDigests A list of EIP-712 digests for the operations in a MultiQuarkOperation
     * @param signature A digital signature, e.g. EIP-712
     * @return Return value from the executed operation
     */
    function executeMultiQuarkOperation(
        QuarkOperation calldata op,
        bytes32[] calldata opDigests,
        bytes calldata signature
    ) external returns (bytes memory) {
        return executeMultiQuarkOperationWithSubmissionToken(op, op.nonce, opDigests, signature);
    }

    /**
     * @notice Executes a first play or a replay of a QuarkOperation that is part of a MultiQuarkOperation via signature
     * @dev Can only be called with signatures from the wallet's signer
     * @param op A QuarkOperation struct
     * @param submissionToken The submission token for the replayable quark operation for QuarkNonceManager. This is initially the `op.nonce`, and for replayable operations, it is the next token in the nonce chain.
     * @param opDigests A list of EIP-712 digests for the operations in a MultiQuarkOperation
     * @param signature A digital signature, e.g. EIP-712
     * @return Return value from the executed operation
     */
    function executeMultiQuarkOperationWithSubmissionToken(
        QuarkOperation calldata op,
        bytes32 submissionToken,
        bytes32[] calldata opDigests,
        bytes calldata signature
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

        return verifySigAndExecuteQuarkOperation(op, submissionToken, multiOpDigest, signature);
    }

    /**
     * @notice Verify a signature and execute a replayable QuarkOperation
     * @param op A QuarkOperation struct
     * @param submissionToken The submission token for the replayable quark operation for QuarkNonceManager. This is initially the `op.nonce`, and for replayable operations, it is the next token in the nonce chain.
     * @param digest A EIP-712 digest for either a QuarkOperation or MultiQuarkOperation to verify the signature against
     * @param signature A digital signature, e.g. EIP-712
     * @return Return value from the executed operation
     */
    function verifySigAndExecuteQuarkOperation(
        QuarkOperation calldata op,
        bytes32 submissionToken,
        bytes32 digest,
        bytes calldata signature
    ) internal returns (bytes memory) {
        if (block.timestamp >= op.expiry) {
            revert SignatureExpired();
        }

        // if the signature check does not revert, the signature is valid
        checkValidSignatureInternal(IHasSignerExecutor(address(this)).signer(), digest, signature);

        // guarantee every script in scriptSources is deployed
        for (uint256 i = 0; i < op.scriptSources.length; ++i) {
            codeJar.saveCode(op.scriptSources[i]);
        }

        nonceManager.submit(op.nonce, op.isReplayable, submissionToken);

        emit QuarkExecution(
            msg.sender, op.scriptAddress, op.nonce, submissionToken, op.isReplayable, ExecutionType.Signature
        );

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

        nonceManager.submit(nonce, false, nonce);

        emit QuarkExecution(msg.sender, scriptAddress, nonce, nonce, false, ExecutionType.Direct);

        return executeScriptInternal(scriptAddress, scriptCalldata, nonce, nonce);
    }

    /**
     * @notice Returns the domain separator for this Quark wallet
     * @return Domain separator
     */
    function getDomainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(NAME)), keccak256(bytes(VERSION)), block.chainid, address(this))
        );
    }

    /**
     * @notice Returns the EIP-712 digest for a QuarkOperation
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
     * @notice Returns the EIP-712 digest for a MultiQuarkOperation
     * @param opDigests A list of EIP-712 digests for the operations in a MultiQuarkOperation
     * @return EIP-712 digest
     */
    function getDigestForMultiQuarkOperation(bytes32[] memory opDigests) public pure returns (bytes32) {
        bytes memory encodedOpDigests = abi.encodePacked(opDigests);
        bytes32 structHash = keccak256(abi.encode(MULTI_QUARK_OPERATION_TYPEHASH, keccak256(encodedOpDigests)));
        return keccak256(abi.encodePacked("\x19\x01", MULTI_QUARK_OPERATION_DOMAIN_SEPARATOR, structHash));
    }

    /**
     * @notice Returns the EIP-712 digest of a QuarkMessage that can be signed by `signer`
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
        // Note: The following logic further encodes the provided `hash` with the wallet's domain
        // to prevent signature replayability for Quark wallets owned by the same `signer`
        bytes32 digest = getDigestForQuarkMessage(abi.encode(hash));
        // If the signature check does not revert, the signature is valid
        checkValidSignatureInternal(IHasSignerExecutor(address(this)).signer(), digest, signature);
        return EIP_1271_MAGIC_VALUE;
    }

    /**
     * @dev If the QuarkWallet is owned by an EOA, isValidSignature confirms
     * that the signature comes from the signer; if the QuarkWallet is owned by
     * a smart contract, isValidSignature relays the `isValidSignature` check
     * to the smart contract; if the smart contract that owns the wallet has no
     * code, the signature will be treated as an EIP-712 signature and revert
     */
    function checkValidSignatureInternal(address signatory, bytes32 digest, bytes memory signature) internal view {
        if (signatory.code.length > 0) {
            // For EIP-1271 smart contract signers, the signature can be of any signature scheme (e.g. BLS, Passkey)
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
            // For EOA signers, this implementation of the QuarkWallet only supports ECDSA signatures
            (address recoveredSigner, ECDSA.RecoverError recoverError) = ECDSA.tryRecover(digest, signature);
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
        bytes32 callbackSlot = CALLBACK_SLOT;
        address oldActiveScript;
        bytes32 oldActiveNonce;
        bytes32 oldActiveSubmissionToken;
        address oldCallback;
        assembly {
            // Cache the previous values in each of the transient slots so they can be restored after executing the script
            oldActiveScript := tload(activeScriptSlot)
            oldActiveNonce := tload(activeNonceSlot)
            oldActiveSubmissionToken := tload(activeSubmissionTokenSlot)
            oldCallback := tload(callbackSlot)

            // Prevent nested operations coming from an outside caller (i.e. not the Quark wallet itself)
            if and(iszero(eq(oldActiveScript, 0)), iszero(eq(caller(), address()))) {
                let errorSignature := 0x0c484db9 // Signature for UnauthorizedNestedOperation()
                let ptr := mload(0x40)
                mstore(ptr, errorSignature)
                // Error signature is left-padded with 0s, so we want to fetch the last 4 bytes starting at the 29th byte
                revert(add(ptr, 0x1c), 0x04)
            }

            // Transiently store the active script
            tstore(activeScriptSlot, scriptAddress)

            // Transiently store the active nonce
            tstore(activeNonceSlot, nonce)

            // Transiently store the active submission token
            tstore(activeSubmissionTokenSlot, submissionToken)

            // Transiently set the callback slot to 0
            tstore(callbackSlot, 0)

            success := delegatecall(gas(), scriptAddress, add(scriptCalldata, 0x20), scriptCalldataLen, 0x0, 0)
            returnSize := returndatasize()

            // Transiently restore the active script
            tstore(activeScriptSlot, oldActiveScript)

            // Transiently restore the active nonce
            tstore(activeNonceSlot, oldActiveNonce)

            // Transiently restore the active submission token
            tstore(activeSubmissionTokenSlot, oldActiveSubmissionToken)

            // Transiently restore the callback slot
            tstore(callbackSlot, oldCallback)
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
            callback := tload(callbackSlot)
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
}
