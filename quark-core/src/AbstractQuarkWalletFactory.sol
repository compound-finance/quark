// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "quark-core/src/QuarkWallet.sol";

/**
 * @title Abstract Quark Wallet Factory
 * @notice An abstract factory for deploying new Quark Wallets at deterministic addresses
 * @author Compound Labs, Inc.
 */
abstract contract AbstractQuarkWalletFactory {
    event WalletDeploy(address indexed signer, address indexed executor, address walletAddress, bytes32 salt);

    /**
     * @notice Major version of the contract
     * @dev This should be a public constant in the implementation contract
     */
    function VERSION() external virtual view returns (uint256);

    /**
     * @notice Returns the EIP-712 domain separator used for signing operations for the given salted wallet
     * @dev Only use for wallets deployed by this factory, or counterfactual wallets that will be deployed;
     * only a wallet with the assumed QuarkWalletMetadata (NAME, VERSION, DOMAIN_TYPEHASH) will work.
     * @return bytes32 The domain separator for the wallet corresponding to the signer and salt
     */
    function DOMAIN_SEPARATOR(address signer, bytes32 salt) external virtual view returns (bytes32);

    /**
     * @notice Create new QuarkWallet for signer, salt pair
     * @dev Will revert if wallet already exists for signer, salt pair; sets the executor for salted wallets to the wallet with salt=DEFAULT_SALT
     * @param signer Address to create a QuarkWallet for
     * @param salt Salt value to use during creation of QuarkWallet
     * @return address Address of the newly-created wallet
     */
    function create(address signer, bytes32 salt) public virtual returns (address payable);

    /**
     * @notice Get QuarkWallet address for signer, salt pair
     * @dev QuarkWallet at returned address may not have been created yet
     * @param signer Address to find QuarkWallet address for
     * @param salt Salt value for QuarkWallet
     * @return address Address of the QuarkWallet for signer, salt pair
     */
    function walletAddressForSignerWithSalt(address signer, bytes32 salt) public virtual view returns (address payable);

    /*===========================================================
     * Shared non-virtual data and abstract implementation logic.
     */

    /// @notice Default initial salt value
    bytes32 public constant DEFAULT_SALT = bytes32(0);

    /**
     * @notice Create new QuarkWallet for signer (with default salt value)
     * @dev Will revert if wallet already exists for signer
     * @param signer Address to create a QuarkWallet for
     * @return address Address of the newly-created wallet
     */
    function create(address signer) external returns (address payable) {
        return create(signer, DEFAULT_SALT);
    }

    /**
     * @notice Get QuarkWallet address for signer (and default salt value)
     * @dev QuarkWallet at returned address may not have been created yet
     * @param signer Address to find QuarkWallet address for
     * @return address Address of the QuarkWallet for signer
     */
    function walletAddressForSigner(address signer) external view returns (address payable) {
        return walletAddressForSignerWithSalt(signer, DEFAULT_SALT);
    }

    /**
     * @notice Create a wallet for signer (and default salt) if it does not exist, then execute operation
     * @param signer Signer to deploy QuarkWallet for and then execute operation with
     * @param op The QuarkOperation to execute on the wallet
     * @param v EIP-712 Signature `v` value
     * @param r EIP-712 Signature `r` value
     * @param s EIP-712 Signature `s` value
     * @return bytes Return value of executing the operation
     */
    function createAndExecute(address signer, QuarkWallet.QuarkOperation memory op, uint8 v, bytes32 r, bytes32 s)
        external
        returns (bytes memory)
    {
        return createAndExecute(signer, DEFAULT_SALT, op, v, r, s);
    }

    /**
     * @notice Create a wallet for signer, salt pair if it does not exist, then execute operation
     * @param signer Signer to deploy QuarkWallet for and then execute operation with
     * @param salt Salt value of QuarkWallet to create and execute operation with
     * @param op The QuarkOperation to execute on the wallet
     * @param v EIP-712 Signature `v` value
     * @param r EIP-712 Signature `r` value
     * @param s EIP-712 Signature `s` value
     * @return bytes Return value of executing the operation
     */
    function createAndExecute(
        address signer,
        bytes32 salt,
        QuarkWallet.QuarkOperation memory op,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public returns (bytes memory) {
        address payable walletAddress = walletAddressForSignerWithSalt(signer, salt);
        if (walletAddress.code.length == 0) {
            create(signer, salt);
        }

        return QuarkWallet(walletAddress).executeQuarkOperation(op, v, r, s);
    }
}
