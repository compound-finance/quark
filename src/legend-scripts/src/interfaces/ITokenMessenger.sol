// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

interface ITokenMessenger {
    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken
    ) external returns (uint64 _nonce);
}
