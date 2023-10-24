// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "./../../src/QuarkWallet.sol";
import "./../../src/QuarkWalletPre.sol";

contract SignatureHelper is Test {
    bytes32 internal constant QUARK_OPERATION_TYPEHASH = keccak256(
        "QuarkOperation(bytes scriptSource,bytes scriptCalldata,uint256 nonce,uint256 expiry,bool allowCallback)"
    );

    bytes32 internal constant QUARK_WALLET_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    function signOp(uint256 privateKey, QuarkWallet wallet, QuarkWallet.QuarkOperation memory op)
        external
        view
        returns (uint8, bytes32, bytes32)
    {
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", wallet.DOMAIN_SEPARATOR(), structHash(op)));
        return vm.sign(privateKey, digest);
    }

    function signOpPre(uint256 privateKey, QuarkWalletPre wallet, QuarkWalletPre.QuarkOperation memory op)
        external
        view
        returns (uint8, bytes32, bytes32)
    {
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", wallet.DOMAIN_SEPARATOR(), structHashPre(op)));
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
                QUARK_OPERATION_TYPEHASH, op.scriptSource, op.scriptCalldata, op.nonce, op.expiry, op.allowCallback
            )
        );
    }

    function structHashPre(QuarkWalletPre.QuarkOperation memory op) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                QUARK_OPERATION_TYPEHASH, op.scriptSource, op.scriptCalldata, op.nonce, op.expiry, op.allowCallback
            )
        );
    }

    function domainSeparator(address walletAddress) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                QUARK_WALLET_DOMAIN_TYPEHASH,
                keccak256(bytes("Quark Wallet")), // name
                keccak256(bytes("1")), // version
                block.chainid,
                walletAddress
            )
        );
    }
}
