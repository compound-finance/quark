pragma solidity 0.8.27;

contract EIP1271Signer {
    bytes4 internal constant EIP_1271_MAGIC_VALUE = 0x1626ba7e;

    bool public approveSignature;

    constructor(bool _approveSignature) {
        approveSignature = _approveSignature;
    }

    function isValidSignature(bytes32, /* messageHash */ bytes memory /* signature */ )
        external
        view
        returns (bytes4)
    {
        if (approveSignature) {
            return EIP_1271_MAGIC_VALUE;
        } else {
            return 0xffffffff;
        }
    }
}

contract EIP1271Reverter {
    function isValidSignature(bytes32, /* messageHash */ bytes memory /* signature */ )
        external
        pure
        returns (bytes4)
    {
        revert();
    }
}
