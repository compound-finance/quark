// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./CodeJar.sol";
import "./QuarkWallet.sol";

/**
 * Broker is a message-passing bridge for signed EIP-712 transactions and
 * a factory for new QuarkWallets at deterministic addresses.
 */
contract QuarkBroker {
    /// @notice Bit-packed nonce values
    /// chainId => userAdress => nonce bucket => nonce
    mapping(uint256 => mapping(address => mapping(uint256 => uint256))) public nonces;

    CodeJar public codeJar;

    /**
     * @notice a QuarkBroker deploys a CodeJar and provides a well-known entrypoint to the rest of the Quark protocol.
     */
    constructor() {
        codeJar = new CodeJar();
    }

    /**
     * @notice create a QuarkWallet at a deterministic address based upon the CodeJar and the underlying owner account address.
     */
    function createWallet(address account) public returns (address) {
        return address(new QuarkWallet{salt: 0}(account, codeJar));
    }

    /**
     * @notice create a QuarkWallet and execute an initial transaction script.
     */
    function createAndExecute(
        address account,
        QuarkWallet.QuarkOperation memory op,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public payable returns (bytes memory) {
        uint256 walletCodeLen;
        address walletAddress = walletAddressForAccount(account);

        assembly {
            walletCodeLen := extcodesize(walletAddress)
        }
        if (walletCodeLen == 0) {
            createWallet(account);
        }

        return QuarkWallet(wallet).executeQuarkOperation(op, v, r, s);
    }

    /**
     * @notice Helper function to return a quark address for a given account.
     */
    function walletAddressForAccount(address account) external view returns (address) {
        return address(uint160(uint(
            keccak256(
                abi.encodePacked(
                    bytes1(0xff),
                    address(this),
                    uint256(0),
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
     * @notice Helper function to return a quark address for a given account.
     */
    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) public {
        (chainId, userAddress, nonce) = abi.decode(any2EvmMessage.data, (uint256, address, uint256));
        _updateNonce(chainId, userAddress, nonce);
    }

    /**
     * @notice Helper function to return a quark address for a given account.
     */
    function _updateNonce(chainId, userAddress, nonce) internal {
        uint256 bucket = nonce >> 8;
        uint256 mask = 1 << (nonce & 0xff);
        nonces[chainId][userAddress][bucket] |= mask;
    }
}
