// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "./../../src/QuarkWallet.sol";

contract SignatureHelper is Test {
    bytes32 internal constant QUARK_OPERATION_TYPEHASH = keccak256(
        "QuarkOperation(bytes scriptSource,bytes scriptCalldata,uint256 nonce,uint256 expiry,bool allowCallback)"
    );

    function signOp(QuarkWallet wallet, QuarkWallet.QuarkOperation memory op, uint256 privateKey)
        public
        view
        returns (uint8, bytes32, bytes32)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                QUARK_OPERATION_TYPEHASH, op.scriptSource, op.scriptCalldata, op.nonce, op.expiry, op.allowCallback
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", wallet.DOMAIN_SEPARATOR(), structHash));
        return vm.sign(privateKey, digest);
    }
}