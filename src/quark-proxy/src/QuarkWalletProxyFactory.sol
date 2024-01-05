// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import {QuarkWallet, QuarkWalletMetadata} from "quark-core/src/QuarkWallet.sol";

import {QuarkMinimalProxy} from "quark-proxy/src/QuarkMinimalProxy.sol";

/**
 * @title Quark Wallet Proxy Factory
 * @notice A factory for deploying Quark Wallet Proxy instances at deterministic addresses
 * @author Compound Labs, Inc.
 */
contract QuarkWalletProxyFactory {
    event WalletDeploy(address indexed signer, address indexed executor, address walletAddress, bytes32 salt);

    /// @notice Major version of the contract
    uint256 public constant VERSION = 1;

    /// @notice Default initial salt value
    bytes32 public constant DEFAULT_SALT = bytes32(0);

    /// @notice Address of QuarkWallet implementation contract
    address public immutable walletImplementation;

    /// @notice Construct a new QuarkWalletProxyFactory with the provided QuarkWallet implementation address
    constructor(address walletImplementation_) {
        walletImplementation = walletImplementation_;
    }

    /**
     * @notice Returns the EIP-712 domain separator used for signing operations for the wallet belonging
     * to the given (signer, executor, salt) triple
     * @dev Only for use for wallets deployed by this factory, or counterfactual wallets that
     * will be deployed with this factory; only a wallet with the expected QuarkWalletMetadata
     * (NAME, VERSION, DOMAIN_TYPEHASH) will work.
     * @return bytes32 The domain separator for the wallet corresponding to the signer and salt
     */
    function DOMAIN_SEPARATOR(address signer, address executor, bytes32 salt) external view returns (bytes32) {
        return keccak256(
            abi.encode(
                QuarkWalletMetadata.DOMAIN_TYPEHASH,
                keccak256(bytes(QuarkWalletMetadata.NAME)),
                keccak256(bytes(QuarkWalletMetadata.VERSION)),
                block.chainid,
                walletAddressForSalt(signer, executor, salt)
            )
        );
    }

    /**
     * @notice Create new QuarkWallet for (signer, executor) pair (with default salt value)
     * @dev Will revert if wallet already exists for signer
     * @param signer Address to set as the signer of the QuarkWallet
     * @param executor Address to set as the executor of the QuarkWallet
     * @return address Address of the newly-created wallet
     */
    function create(address signer, address executor) external returns (address payable) {
        return create(signer, executor, DEFAULT_SALT);
    }

    /**
     * @notice Create new QuarkWallet for (signer, executor, salt) triple
     * @dev Will revert if wallet already exists for (signer, executor, salt) triple
     * @param signer Address to set as the signer of the QuarkWallet
     * @param executor Address to set as the executor of the QuarkWallet
     * @param salt Salt value to use during creation of QuarkWallet
     * @return address Address of the newly-created wallet
     */
    function create(address signer, address executor, bytes32 salt) public returns (address payable) {
        address payable proxyAddress =
            payable(address(new QuarkMinimalProxy{salt: salt}(walletImplementation, signer, executor)));
        emit WalletDeploy(signer, executor, proxyAddress, salt);
        return proxyAddress;
    }

    /**
     * @notice Create a wallet for (signer, executor) pair (and default salt) if it does not exist, then execute operation
     * @param signer Address to set as the signer of the QuarkWallet
     * @param executor Address to set as the executor of the QuarkWallet
     * @param op The QuarkOperation to execute on the wallet
     * @param v EIP-712 Signature `v` value
     * @param r EIP-712 Signature `r` value
     * @param s EIP-712 Signature `s` value
     * @return bytes Return value of executing the operation
     */
    function createAndExecute(
        address signer,
        address executor,
        QuarkWallet.QuarkOperation memory op,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (bytes memory) {
        return createAndExecute(signer, executor, DEFAULT_SALT, op, v, r, s);
    }

    /**
     * @notice Create a wallet for (signer, executor, salt) triple if it does not exist, then execute operation
     * @param signer Address to set as the signer of the QuarkWallet
     * @param executor Address to set as the executor of the QuarkWallet
     * @param salt Salt value of QuarkWallet to create and execute operation with
     * @param op The QuarkOperation to execute on the wallet
     * @param v EIP-712 Signature `v` value
     * @param r EIP-712 Signature `r` value
     * @param s EIP-712 Signature `s` value
     * @return bytes Return value of executing the operation
     */
    function createAndExecute(
        address signer,
        address executor,
        bytes32 salt,
        QuarkWallet.QuarkOperation memory op,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public returns (bytes memory) {
        address payable walletAddress = walletAddressForSalt(signer, executor, salt);
        if (walletAddress.code.length == 0) {
            create(signer, executor, salt);
        }

        return QuarkWallet(walletAddress).executeQuarkOperation(op, v, r, s);
    }

    /**
     * @notice Derive QuarkWallet address for (signer, executor) pair (and default salt value)
     * @dev QuarkWallet at returned address may not yet have been created
     * @param signer Address of the signer for which to derive a QuarkWallet address
     * @param executor Address of the executor for which to derive a QuarkWallet address
     * @return address Address of the derived QuarkWallet for (signer, executor) pair
     */
    function walletAddressFor(address signer, address executor) external view returns (address payable) {
        return walletAddressForSalt(signer, executor, DEFAULT_SALT);
    }

    /**
     * @notice Derive QuarkWallet address for (signer, executor, salt) triple
     * @dev QuarkWallet at returned address may not yet have been created
     * @param signer Address of the signer for which to derive a QuarkWallet address
     * @param executor Address of the executor for which to derive a QuarkWallet address
     * @param salt Salt value for which to derive a QuarkWallet address
     * @return address Address of the derived QuarkWallet for (signer, executor, salt) triple
     */
    function walletAddressForSalt(address signer, address executor, bytes32 salt)
        public
        view
        returns (address payable)
    {
        return walletAddressForInternal(signer, executor, salt);
    }

    /// @dev Get the deterministic address of a QuarkWallet for a given (signer, executor, salt) triple
    function walletAddressForInternal(address signer, address executor, bytes32 salt)
        internal
        view
        returns (address payable)
    {
        return payable(
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                bytes1(0xff),
                                address(this),
                                salt,
                                keccak256(
                                    abi.encodePacked(
                                        type(QuarkMinimalProxy).creationCode,
                                        abi.encode(walletImplementation),
                                        abi.encode(signer),
                                        abi.encode(executor)
                                    )
                                )
                            )
                        )
                    )
                )
            )
        );
    }
}
