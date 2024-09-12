// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import "forge-std/Test.sol";
import "quark-core/src/QuarkWallet.sol";

contract SignatureHelper is Test {
    function signOp(uint256 privateKey, QuarkWallet wallet, QuarkWallet.QuarkOperation memory op)
        external
        view
        returns (uint8, bytes32, bytes32)
    {
        bytes32 digest = opDigest(address(wallet), op);
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
        bytes32 digest = opDigest(walletAddress, op);
        return vm.sign(privateKey, digest);
    }

    function signMultiOp(uint256 privateKey, bytes32[] memory opDigests)
        external
        pure
        returns (uint8, bytes32, bytes32)
    {
        bytes32 digest = multiOpDigest(opDigests);
        return vm.sign(privateKey, digest);
    }

    function opDigest(address walletAddress, QuarkWallet.QuarkOperation memory op) public view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator(walletAddress), opStructHash(op)));
    }

    function multiOpDigest(bytes32[] memory opDigests) public pure returns (bytes32) {
        return keccak256(
            abi.encodePacked("\x19\x01", domainSeparatorForMultiQuarkOperation(), multiOpStructHash(opDigests))
        );
    }

    function opStructHash(QuarkWallet.QuarkOperation memory op) public pure returns (bytes32) {
        bytes memory encodedArray;
        for (uint256 i = 0; i < op.scriptSources.length; ++i) {
            encodedArray = abi.encodePacked(encodedArray, keccak256(op.scriptSources[i]));
        }

        return keccak256(
            abi.encode(
                QuarkWalletMetadata.QUARK_OPERATION_TYPEHASH,
                op.nonce,
                op.isReplayable,
                op.scriptAddress,
                keccak256(encodedArray),
                keccak256(op.scriptCalldata),
                op.expiry
            )
        );
    }

    function multiOpStructHash(bytes32[] memory opDigests) public pure returns (bytes32) {
        bytes memory encodedArray;
        for (uint256 i = 0; i < opDigests.length; ++i) {
            encodedArray = abi.encodePacked(encodedArray, opDigests[i]);
        }

        return keccak256(abi.encode(QuarkWalletMetadata.MULTI_QUARK_OPERATION_TYPEHASH, keccak256(encodedArray)));
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

    function domainSeparatorForMultiQuarkOperation() public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                QuarkWalletMetadata.MULTI_QUARK_OPERATION_DOMAIN_TYPEHASH,
                keccak256(bytes(QuarkWalletMetadata.NAME)),
                keccak256(bytes(QuarkWalletMetadata.VERSION))
            )
        );
    }
}
