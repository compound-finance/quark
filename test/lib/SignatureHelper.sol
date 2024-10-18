// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import "forge-std/Test.sol";
import "quark-core/src/QuarkWallet.sol";

contract SignatureHelper is Test {
    error InvalidSignatureLength();

    function signOp(uint256 privateKey, QuarkWallet wallet, QuarkWallet.QuarkOperation memory op)
        external
        view
        returns (bytes memory)
    {
        bytes32 digest = opDigest(address(wallet), op);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    /*
     * @dev for use when you need to sign an operation for a wallet that has not been created yet
     */
    function signOpForAddress(uint256 privateKey, address walletAddress, QuarkWallet.QuarkOperation memory op)
        external
        view
        returns (bytes memory)
    {
        bytes32 digest = opDigest(walletAddress, op);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function signMultiOp(uint256 privateKey, bytes32[] memory opDigests) external pure returns (bytes memory) {
        bytes32 digest = multiOpDigest(opDigests);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function decodeSignature(bytes memory signature) external pure returns (uint8 v, bytes32 r, bytes32 s) {
        if (signature.length != 65) {
            revert InvalidSignatureLength();
        }
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
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
