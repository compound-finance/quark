// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {CodeJar} from "quark-core/src/CodeJar.sol";
import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";
import {QuarkWalletMetadata, QuarkWalletStubbed} from "quark-core/src/QuarkWallet.sol";

import {AbstractQuarkWalletFactory} from "quark-core/src/AbstractQuarkWalletFactory.sol";

import {QuarkMinimalProxy} from "quark-proxy/src/QuarkMinimalProxy.sol";

/**
 * @title Quark Wallet Proxy Factory
 * @notice A factory for deploying new Quark Proxys at deterministic addresses
 * @author Compound Labs, Inc.
 */
contract QuarkWalletProxyFactory is AbstractQuarkWalletFactory {
    /// @notice Major version of the contract
    uint256 public override constant VERSION = 1;

    /// @notice Address of CodeJar contract
    CodeJar public immutable codeJar;

    /// @notice Address of QuarkStateManager contract
    QuarkStateManager public immutable stateManager;

    /// @notice Address of QuarkWallet implementation contract
    address public immutable walletImplementation;

    /// @notice Construct a new QuarkProxyFactory, deploying a CodeJar, QuarkStateManager, and implementation QuarkWallet as well
    constructor() {
        codeJar = new CodeJar();
        stateManager = new QuarkStateManager();
        walletImplementation = address(new QuarkWalletStubbed{salt: 0}(codeJar, stateManager));
    }

    /**
     * @notice Returns the EIP-712 domain separator used for signing operations for the given salted wallet
     * @dev Only use for wallets deployed by this factory, or counterfactual wallets that will be deployed;
     * only a wallet with the assumed QuarkWalletMetadata (NAME, VERSION, DOMAIN_TYPEHASH) will work.
     * @return bytes32 The domain separator for the wallet corresponding to the signer and salt
     */
    function DOMAIN_SEPARATOR(address signer, bytes32 salt) external override view returns (bytes32) {
        return keccak256(
            abi.encode(
                QuarkWalletMetadata.DOMAIN_TYPEHASH,
                keccak256(bytes(QuarkWalletMetadata.NAME)),
                keccak256(bytes(QuarkWalletMetadata.VERSION)),
                block.chainid,
                walletAddressForSignerWithSalt(signer, salt)
            )
        );
    }

    /**
     * @notice Create new QuarkWallet for signer, salt pair
     * @dev Will revert if wallet already exists for signer, salt pair; sets the executor for salted wallets to the wallet with salt=DEFAULT_SALT
     * @param signer Address to create a QuarkWallet for
     * @param salt Salt value to use during creation of QuarkWallet
     * @return address Address of the newly-created wallet
     */
    function create(address signer, bytes32 salt) public override returns (address payable) {
        address executor;
        if (salt != DEFAULT_SALT) {
            executor = walletAddressForSignerWithSalt(signer, DEFAULT_SALT);
        } else {
            executor = address(0);
        }
        address payable proxyAddress =
            payable(address(new QuarkMinimalProxy{salt: salt}(walletImplementation, signer, executor)));
        emit WalletDeploy(signer, executor, proxyAddress, salt);
        return proxyAddress;
    }

    /**
     * @notice Get QuarkWallet address for signer, salt pair
     * @dev QuarkWallet at returned address may not have been created yet
     * @param signer Address to find QuarkWallet address for
     * @param salt Salt value for QuarkWallet
     * @return address Address of the QuarkWallet for signer, salt pair
     */
    function walletAddressForSignerWithSalt(address signer, bytes32 salt) public override view returns (address payable) {
        address executor;
        if (salt != DEFAULT_SALT) {
            executor = walletAddressForSignerInternal(signer, address(0), DEFAULT_SALT);
        } else {
            executor = address(0);
        }
        return walletAddressForSignerInternal(signer, executor, salt);
    }

    /// @dev Get the deterministic address of a QuarkWallet with a given (signer, executor, salt) permutation
    function walletAddressForSignerInternal(address signer, address executor, bytes32 salt)
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
