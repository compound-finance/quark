// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.21;

import {CodeJar} from "./CodeJar.sol";
import {QuarkStateManager} from "./QuarkStateManager.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

library QuarkWalletMetadata {
    /// @notice QuarkWallet contract name
    string public constant NAME = "Quark Wallet";

    /// @notice QuarkWallet contract major version
    string public constant VERSION = "1";

    /// @notice The EIP-712 typehash for authorizing an operation for this version of QuarkWallet
    bytes32 public constant QUARK_OPERATION_TYPEHASH = keccak256(
        "QuarkOperation(uint96 nonce,address scriptAddress,bytes scriptSource,bytes scriptCalldata,uint256 expiry)"
    );

    /// @notice The EIP-712 domain typehash for this version of QuarkWallet
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
}

contract QuarkWallet is IERC1271 {
    error AmbiguousScript();
    error BadSignatory();
    error InvalidEIP1271Signature();
    error InvalidSignature();
    error NoActiveCallback();
    error QuarkCallError(bytes);
    error SignatureExpired();
    error Unauthorized();

    /// @notice Address of the EOA signer or the EIP-1271 contract that verifies signed operations for this wallet
    address public immutable signer;

    /// @notice Address of the executor contract, if any, empowered to direct-execute unsigned operations for this wallet
    address public immutable executor;

    /// @notice Address of CodeJar contract used to save transaction script source code
    CodeJar public immutable codeJar;

    /// @notice Address of QuarkStateManager contract that manages nonces and nonce-namespaced transaction script storage
    QuarkStateManager public immutable stateManager;

    /// @notice Name of contract
    string public constant NAME = QuarkWalletMetadata.NAME;

    /// @notice The major version of this contract
    string public constant VERSION = QuarkWalletMetadata.VERSION;

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

    constructor(address signer_, address executor_, CodeJar codeJar_, QuarkStateManager stateManager_) {
        signer = signer_;
        executor = executor_;
        codeJar = codeJar_;
        stateManager = stateManager_;
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
        payable
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
                QuarkWalletMetadata.QUARK_OPERATION_TYPEHASH,
                op.nonce,
                op.scriptAddress,
                op.scriptSource,
                op.scriptCalldata,
                op.expiry
            )
        );
        bytes32 domainSeparator = keccak256(
            abi.encode(
                QuarkWalletMetadata.DOMAIN_TYPEHASH,
                keccak256(bytes(QuarkWalletMetadata.NAME)),
                keccak256(bytes(QuarkWalletMetadata.VERSION)),
                block.chainid,
                address(this)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // if the signature check does not revert, the signature is valid
        checkValidSignatureInternal(signer, digest, v, r, s);

        // if scriptAddress not given, derive deterministic address from bytecode
        address scriptAddress = op.scriptAddress;
        if (scriptAddress == address(0)) {
            scriptAddress = codeJar.saveCode(op.scriptSource);
        }

        return stateManager.setActiveNonceAndCallback{value: msg.value}(op.nonce, scriptAddress, op.scriptCalldata);
    }

    /**
     * @notice Execute a transaction script directly
     * @dev Can only be called by the wallet's signer or executor
     * @param nonce Nonce for the operation; must be unused
     * @param scriptAddress Address for the script to execute
     * @param scriptCalldata Encoded call to invoke on the script
     * @return Return value from the executed operation
     */
    function executeScript(uint96 nonce, address scriptAddress, bytes calldata scriptCalldata)
        external
        payable
        returns (bytes memory)
    {
        // only allow the executor for the wallet to use unsigned execution
        if (msg.sender != executor) {
            revert Unauthorized();
        }
        return stateManager.setActiveNonceAndCallback{value: msg.value}(nonce, scriptAddress, scriptCalldata);
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
        checkValidSignatureInternal(signer, hash, v, r, s);
        return EIP_1271_MAGIC_VALUE;
    }

    /*
     * @dev If the QuarkWallet is owned by an EOA, isValidSignature confirms
     * that the signature comes from the signer; if the QuarkWallet is owned by
     * a smart contract, isValidSignature relays the `isValidSignature` to the
     * smart contract; if the smart contract that owns the wallet has no code,
     * the signature will be treated as an EIP-712 signature and revert
     */
    function checkValidSignatureInternal(address signatory, bytes32 digest, uint8 v, bytes32 r, bytes32 s)
        internal
        view
    {
        // a contract deployed with empty code will be treated as an EOA and will revert
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
     * @notice Execute a QuarkOperation with its nonce locked and with access to private nonce-scoped storage.
     * @dev Can only be called by stateManager during setActiveNonceAndCallback()
     * @param scriptAddress Address of script to execute
     * @param scriptCalldata Encoded calldata for the call to execute on the scriptAddress
     * @return Result of executing the script, encoded as bytes
     */
    function executeScriptWithNonceLock(address scriptAddress, bytes memory scriptCalldata)
        external
        payable
        returns (bytes memory)
    {
        require(msg.sender == address(stateManager));

        bool success;
        uint256 returnSize;
        uint256 scriptCalldataLen = scriptCalldata.length;
        assembly {
            // Note: CALLCODE is used to set the QuarkWallet as the `msg.sender`
            success := callcode(gas(), scriptAddress, callvalue(), add(scriptCalldata, 0x20), scriptCalldataLen, 0x0, 0)
            returnSize := returndatasize()
        }

        bytes memory returnData = new bytes(returnSize);
        assembly {
            returndatacopy(add(returnData, 0x20), 0x00, returnSize)
        }

        if (!success) {
            revert QuarkCallError(returnData);
        }

        return returnData;
    }

    fallback(bytes calldata data) external returns (bytes memory) {
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
