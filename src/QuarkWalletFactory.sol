// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./CodeJar.sol";
import "./QuarkWallet.sol";

contract QuarkWalletFactory {
    event WalletDeploy(address indexed account, address indexed walletAddress, bytes32 salt);

    /// @notice Major version of the contract 
    uint public constant VERSION = 1;

    /// @notice Address of CodeJar contract
    CodeJar public immutable codeJar;

    constructor() {
        codeJar = new CodeJar();
    }

    /**
     * @notice Create new QuarkWallet for account (with default salt value)
     * @dev Will revert if wallet already exists for account
     * @param account Address to create a QuarkWallet for
     * @return address Address of the newly-created wallet
     */
    function create(address account) public returns (address) {
        return create(account, 0);
    }

    /**
     * @notice Create new QuarkWallet for account, salt pair
     * @dev Will revert if wallet already exists for account, salt pair
     * @param account Address to create a QuarkWallet for
     * @param salt Salt value to use during creation of QuarkWallet
     * @return address Address of the newly-created wallet
     */
    function create(address account, bytes32 salt) public returns (address) {
        address walletAddress = address(new QuarkWallet{salt: salt}(account, codeJar));
        emit WalletDeploy(account, walletAddress, salt);
        return walletAddress;
    }

    /**
     * @notice Get QuarkWallet address for account (and default salt value)
     * @dev QuarkWallet at returned address may not have been created yet, but 
     * @param account Address to find QuarkWallet address for
     * @return address Address of the QuarkWallet for account
     */
    function walletAddressForAccount(address account) external view returns (address) {
        return walletAddressForAccount(account, 0);
    }

    /**
     * @notice Get QuarkWallet address for account, salt pair
     * @dev QuarkWallet at returned address may not have been created yet, but 
     * @param account Address to find QuarkWallet address for
     * @param salt Salt value for QuarkWallet
     * @return address Address of the QuarkWallet for account, salt pair
     */
    function walletAddressForAccount(address account, bytes32 salt) public view returns (address) {
        return address(uint160(uint(
            keccak256(
                abi.encodePacked(
                    bytes1(0xff),
                    address(this),
                    salt,
                    keccak256(
                        abi.encodePacked(
                            type(QuarkWallet).creationCode,
                            abi.encode(account),
                            abi.encode(address(codeJar))
                        )
                    )
                )
            )))
        );
    }

    /**
     * @notice Create a wallet for account (and default salt) if it does not exist, then execute operation
     * @param account Account to deploy QuarkWallet for and then execute operation with
     * @param op The QuarkOperation to execute on the wallet
     * @param v EIP-712 Signature `v` value
     * @param r EIP-712 Signature `r` value
     * @param s EIP-712 Signature `s` value
     * @return bytes Return value of executing the operation
     */
    function createAndExecute(
        address account,
        QuarkWallet.QuarkOperation memory op,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public payable returns (bytes memory) {
        return createAndExecute(account, 0, op, v, r, s);
    }

    /**
     * @notice Create a wallet for account, salt pair if it does not exist, then execute operation
     * @param account Account to deploy QuarkWallet for and then execute operation with
     * @param salt Salt value of QuarkWallet to create and execute operation with
     * @param op The QuarkOperation to execute on the wallet
     * @param v EIP-712 Signature `v` value
     * @param r EIP-712 Signature `r` value
     * @param s EIP-712 Signature `s` value
     * @return bytes Return value of executing the operation
     */
    function createAndExecute(
        address account,
        bytes32 salt,
        QuarkWallet.QuarkOperation memory op,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public payable returns (bytes memory) {
        uint256 walletCodeLen;
        address walletAddress = walletAddressForAccount(account, salt);

        assembly {
            walletCodeLen := extcodesize(walletAddress)
        }
        if (walletCodeLen == 0) {
            create(account, salt);
        }

        return QuarkWallet(walletAddress).executeQuarkOperation(op, v, r, s);
    }
}
