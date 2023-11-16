// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "./../../src/QuarkWallet.sol";

contract SignatureHelper is Test {
    bytes32 internal constant QUARK_OPERATION_TYPEHASH = QuarkWalletMetadata.QUARK_OPERATION_TYPEHASH;

    bytes32 internal constant QUARK_WALLET_DOMAIN_TYPEHASH = QuarkWalletMetadata.DOMAIN_TYPEHASH;

    function signOp(uint256 privateKey, QuarkWallet wallet, QuarkWallet.QuarkOperation memory op)
        external
        view
        returns (uint8, bytes32, bytes32)
    {
        bytes32 digest = QuarkWalletMetadata.DIGEST(address(wallet), op);
        return vm.sign(privateKey, digest);
    }

    /*
     * @dev for use when you need to sign an operation for a wallet that has not been created yet
     */
    function signOpForAddress(uint256 privateKey, address walletAddress, QuarkWallet.QuarkOperation memory op)
        external
        view
        returns (uint8, bytes32, bytes32)
    {
        bytes32 digest = QuarkWalletMetadata.DIGEST(walletAddress, op);
        return vm.sign(privateKey, digest);
    }

    function structHash(QuarkWallet.QuarkOperation memory op) internal pure returns (bytes32) {
        return QuarkWalletMetadata.STRUCT_HASH(op);
    }

    function domainSeparator(address walletAddress) internal view returns (bytes32) {
        return QuarkWalletMetadata.DOMAIN_SEPARATOR(walletAddress);
    }
}
