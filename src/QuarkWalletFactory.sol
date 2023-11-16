// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "./CodeJar.sol";
import "./QuarkWallet.sol";
import "./QuarkStateManager.sol";

contract QuarkWalletFactory {
    event WalletDeploy(address indexed signer, address indexed executor, address walletAddress, bytes32 salt);

    /// @notice Major version of the contract
    uint256 public constant VERSION = 1;

    /// @notice Default initial salt value
    bytes32 public constant DEFAULT_SALT = bytes32(0);

    /// @notice Address of CodeJar contract
    CodeJar public immutable codeJar;

    /// @notice Address of QuarkStateManager contract
    QuarkStateManager public immutable stateManager;

    constructor() {
        codeJar = new CodeJar();
        stateManager = new QuarkStateManager();
    }

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
     * @notice Create new QuarkWallet for signer, salt pair
     * @dev Will revert if wallet already exists for signer, salt pair; sets the executor for salted wallets to the wallet with salt=DEFAULT_SALT
     * @param signer Address to create a QuarkWallet for
     * @param salt Salt value to use during creation of QuarkWallet
     * @return address Address of the newly-created wallet
     */
    function create(address signer, bytes32 salt) public returns (address payable) {
        address executor;
        if (salt != DEFAULT_SALT) {
            executor = walletAddressForSignerWithSalt(signer, DEFAULT_SALT);
        } else {
            executor = address(0);
        }
        address payable walletAddress =
            payable(address(new QuarkWallet{salt: salt}(signer, executor, codeJar, stateManager)));
        emit WalletDeploy(signer, executor, walletAddress, salt);
        return walletAddress;
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
     * @notice Get QuarkWallet address for signer, salt pair
     * @dev QuarkWallet at returned address may not have been created yet
     * @param signer Address to find QuarkWallet address for
     * @param salt Salt value for QuarkWallet
     * @return address Address of the QuarkWallet for signer, salt pair
     */
    function walletAddressForSignerWithSalt(address signer, bytes32 salt) public view returns (address payable) {
        address executor;
        if (salt != DEFAULT_SALT) {
            executor = walletAddressForSignerInternal(signer, address(0), DEFAULT_SALT);
        } else {
            executor = address(0);
        }
        return walletAddressForSignerInternal(signer, executor, salt);
    }

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
                                        type(QuarkWallet).creationCode,
                                        abi.encode(signer),
                                        abi.encode(executor),
                                        abi.encode(address(codeJar)),
                                        abi.encode(address(stateManager))
                                    )
                                )
                            )
                        )
                    )
                )
            )
        );
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
        payable
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
    ) public payable returns (bytes memory) {
        address payable walletAddress = walletAddressForSignerWithSalt(signer, salt);
        if (walletAddress.code.length == 0) {
            create(signer, salt);
        }

        return QuarkWallet(walletAddress).executeQuarkOperation{value: msg.value}(op, v, r, s);
    }
}
