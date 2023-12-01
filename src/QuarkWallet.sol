// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {CodeJar} from "./CodeJar.sol";
import {QuarkStateManager} from "./QuarkStateManager.sol";
import {ECDSA} from "openzeppelin/utils/cryptography/ECDSA.sol";
import {IERC1271} from "openzeppelin/interfaces/IERC1271.sol";
import "forge-std/console.sol";

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
        "QuarkOperation(uint96 nonce,address scriptAddress,bytes scriptSource,bytes scriptCalldata,uint256 expiry)"
    );

    /// @notice The EIP-712 domain typehash for this version of QuarkWallet
    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
}

/**
 * @title Quark Wallet
 * @notice A smart wallet that can run transaction scripts
 * @author Compound Labs, Inc.
 */
contract QuarkWallet is IERC1271 {
    error AmbiguousScript();
    error BadSignatory();
    error InvalidEIP1271Signature();
    error InvalidSignature();
    error NoActiveCallback();
    error SignatureExpired();
    error Unauthorized();

    /// @notice Address of the EOA signer or the EIP-1271 contract that verifies signed operations for this wallet
    // address public immutable signer;

    // /// @notice Address of the executor contract, if any, empowered to direct-execute unsigned operations for this wallet
    // address public immutable executor;

    address public immutable impl;

    address public immutable initializer;

    /// @notice Address of CodeJar contract used to deploy transaction script source code
    CodeJar public immutable codeJar;

    /// @notice Address of QuarkStateManager contract that manages nonces and nonce-namespaced transaction script storage
    QuarkStateManager public immutable stateManager;

    /// @notice Name of contract
    string public constant NAME = QuarkWalletMetadata.NAME;

    /// @notice The major version of this contract
    string public constant VERSION = QuarkWalletMetadata.VERSION;

    /// @dev The EIP-712 domain typehash for this wallet
    bytes32 internal constant DOMAIN_TYPEHASH = QuarkWalletMetadata.DOMAIN_TYPEHASH;

    /// @dev The EIP-712 typehash for authorizing an operation for this wallet
    bytes32 internal constant QUARK_OPERATION_TYPEHASH = QuarkWalletMetadata.QUARK_OPERATION_TYPEHASH;

    /// @notice Well-known stateManager key for the currently executing script's callback address (if any)
    bytes32 public constant CALLBACK_KEY = keccak256("callback.v1.quark");

    /// @notice The magic value to return for valid ERC1271 signature
    bytes4 internal constant EIP_1271_MAGIC_VALUE = 0x1626ba7e;

    /// @notice The structure of a signed operation to execute in the context of this wallet
    struct QuarkOperation {
        /// @notice Nonce identifier for the operation
        uint96 nonce;
        /**
         * @notice The address of the transaction script to run
         * @dev Should be set as address(0) when `scriptSource` is non-empty
         */
        address scriptAddress;
        /**
         * @notice The runtime bytecode of the transaction script to run
         * @dev Should be set to empty bytes when `scriptAddress` is non-zero
         */
        bytes scriptSource;
        /// @notice Encoded function selector + arguments to invoke on the script contract
        bytes scriptCalldata;
        /// @notice Expiration time for the signature corresponding to this operation
        uint256 expiry;
    }

    /**
     * @notice Construct a new QuarkWallet
     * @param signer_ The address that is allowed to sign QuarkOperations for this wallet
     * @param executor_ The address that is allowed to directly execute Quark scripts for this wallet
     * @param codeJar_ The CodeJar contract used to deploy scripts
     * @param stateManager_ The QuarkStateManager contract used to write/read nonces and storage for this wallet
     */
    constructor(address signer_, address executor_, CodeJar codeJar_, QuarkStateManager stateManager_) {
        codeJar = codeJar_;
        stateManager = stateManager_;
        impl = address(0);
        initializer = msg.sender;
    }

    function initialize(address signer, address executor) public {
        require(msg.sender == initializer, "QuarkWalletDirectProxy: not initializer");
        stateManager.writeImmutable(bytes32("signer"), bytes32(uint256(uint160(signer))));
        stateManager.writeImmutable(bytes32("executor"), bytes32(uint256(uint160(executor))));
    }

    function signer() public view returns (address) {
        return address(uint160(uint256(stateManager.readImmutable("signer"))));
    }

    function executor() public view returns (address) {
        return address(uint160(uint256(stateManager.readImmutable("executor"))));
    }

    /**
     * @notice Execute a QuarkOperation via signature
     * @dev Can only be called with signatures from the wallet's signer
     * @param op A QuarkOperation struct
     * @param v EIP-712 signature v value
     * @param r EIP-712 signature r value
     * @param s EIP-712 signature s value
     * @return return value from the executed operation
     */
    function executeQuarkOperation(QuarkOperation calldata op, uint8 v, bytes32 r, bytes32 s)
        external
        returns (bytes memory)
    {
        if (block.timestamp >= op.expiry) {
            revert SignatureExpired();
        }

        /*
         * At most one of scriptAddress or scriptSource may be provided;
         * specifying both adds cost (ie. wasted bytecode) for no benefit.
         */
        if ((op.scriptAddress != address(0)) && (op.scriptSource.length > 0)) {
            revert AmbiguousScript();
        }

        bytes32 structHash = keccak256(
            abi.encode(
                QUARK_OPERATION_TYPEHASH,
                op.nonce,
                op.scriptAddress,
                keccak256(op.scriptSource),
                keccak256(op.scriptCalldata),
                op.expiry
            )
        );
        bytes32 domainSeparator = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(NAME)), keccak256(bytes(VERSION)), block.chainid, address(this))
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // if the signature check does not revert, the signature is valid
        checkValidSignatureInternal(address(uint160(uint256(stateManager.readImmutable("signer")))), digest, v, r, s);

        // if scriptAddress not given, derive deterministic address from bytecode
        address scriptAddress = op.scriptAddress;
        if (scriptAddress == address(0)) {
            scriptAddress = codeJar.saveCode(op.scriptSource);
        }

        return stateManager.setActiveNonceAndCallback(op.nonce, scriptAddress, op.scriptCalldata);
    }

    /**
     * @notice Execute a transaction script directly
     * @dev Can only be called by the wallet's executor
     * @param nonce Nonce for the operation; must be unused
     * @param scriptAddress Address for the script to execute
     * @param scriptCalldata Encoded call to invoke on the script
     * @return Return value from the executed operation
     */
    function executeScript(uint96 nonce, address scriptAddress, bytes calldata scriptCalldata)
        external
        returns (bytes memory)
    {
        // only allow the executor for the wallet to use unsigned execution
        if (msg.sender != address(uint160(uint256(stateManager.readImmutable("executor"))))) {
            revert Unauthorized();
        }
        return stateManager.setActiveNonceAndCallback(nonce, scriptAddress, scriptCalldata);
    }

    /**
     * @notice Checks whether an EIP-1271 signature is valid
     * @dev If the QuarkWallet is owned by an EOA, isValidSignature confirms
     * that the signature comes from the signer; if the QuarkWallet is owned by
     * a smart contract, isValidSignature relays the `isValidSignature` to the
     * smart contract
     * @param hash Hash of the signed data
     * @param signature Signature byte array associated with data
     * @return bytes4 Returns the ERC-1271 "magic value" that indicates that the signature is valid
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
        // if the signature check does not revert, the signature is valid
        checkValidSignatureInternal(address(uint160(uint256(stateManager.readImmutable("signer")))), hash, v, r, s);
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
                console.log("recoveredSigner: %s", recoveredSigner);
                console.log("signatory: %s", signatory);
                revert BadSignatory();
            }
        }
    }

    /**
     * @notice Execute a QuarkOperation with a lock acquired on nonce-namespaced storage
     * @dev Can only be called by stateManager during setActiveNonceAndCallback()
     * @param scriptAddress Address of script to execute
     * @param scriptCalldata Encoded calldata for the call to execute on the scriptAddress
     * @return Result of executing the script, encoded as bytes
     */
    function executeScriptWithNonceLock(address scriptAddress, bytes memory scriptCalldata)
        external
        returns (bytes memory)
    {
        require(msg.sender == address(stateManager));

        bool success;
        uint256 returnSize;
        uint256 scriptCalldataLen = scriptCalldata.length;
        assembly {
            // Note: CALLCODE is used to set the QuarkWallet as the `msg.sender`
            success :=
                callcode(gas(), scriptAddress, /* value */ 0, add(scriptCalldata, 0x20), scriptCalldataLen, 0x0, 0)
            returnSize := returndatasize()
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
        address callback = address(uint160(uint256(stateManager.read(CALLBACK_KEY))));
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

    receive() external payable {}
}
