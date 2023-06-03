// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

contract SigUtils {
    bytes32 internal DOMAIN_SEPARATOR;

    constructor(bytes32 _DOMAIN_SEPARATOR) {
        DOMAIN_SEPARATOR = _DOMAIN_SEPARATOR;
    }

    // keccak256("TrxScript(address account,uint32 nonce,uint32[] reqs,bytes trxScript,uint256 expiry)");
    bytes32 public constant TRX_SCRIPT_TYPEHASH =
        0x3e383bf3ede950a478c224dbd59d29cf8d03b2807bd87d26770a3d63ddbb31c9;

    struct TrxScript {
        address account;
        uint32 nonce;
        uint32[] reqs;
        bytes trxScript;
        uint256 expiry;
    }

    // computes the hash of a trxScript
    function getStructHash(TrxScript memory _trxScript)
        internal
        pure
        returns (bytes32)
    {
        return
            keccak256(
                abi.encode(
                    TRX_SCRIPT_TYPEHASH,
                    _trxScript.account,
                    _trxScript.nonce,
                    keccak256(abi.encode(_trxScript.reqs)),
                    keccak256(_trxScript.trxScript),
                    _trxScript.expiry
                )
            );
    }

    // computes the hash of the fully encoded EIP-712 message for the domain, which can be used to recover the signer
    function getTypedDataHash(TrxScript memory _trxScript)
        public
        view
        returns (bytes32)
    {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    getStructHash(_trxScript)
                )
            );
    }
}
