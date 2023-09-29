// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./CodeJar.sol";
import "./QuarkWallet.sol";

/**
 * Broker is a message-passing bridge for signed EIP-712 transactions and
 * a factory for new QuarkWallets at deterministic addresses.
 */
contract QuarkBroker {
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
    function create(address account) public returns (address) {
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
        address wallet = create(account);
        return QuarkWallet(wallet).executeQuarkOperation(op, v, r, s);
    }
}
