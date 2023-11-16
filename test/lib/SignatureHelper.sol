// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "./../../src/QuarkWallet.sol";

contract SignatureHelper is Test {
    function signOp(uint256 privateKey, QuarkWallet wallet, QuarkWallet.QuarkOperation memory op)
        external
        view
        returns (uint8, bytes32, bytes32)
    {
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator(address(wallet)), structHash(op)));
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
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator(walletAddress), structHash(op)));
        return vm.sign(privateKey, digest);
    }

    function structHash(QuarkWallet.QuarkOperation memory op) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                QuarkWalletMetadata.QUARK_OPERATION_TYPEHASH,
                op.nonce,
                op.scriptAddress,
                op.scriptSource,
                op.scriptCalldata,
                op.expiry
            )
        );
    }

    function domainSeparator(address walletAddress) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                QuarkWalletMetadata.DOMAIN_TYPEHASH,
                keccak256(bytes(QuarkWalletMetadata.NAME)),
                keccak256(bytes(QuarkWalletMetadata.VERSION)),
                block.chainid,
                walletAddress
            )
        );
    }
}
