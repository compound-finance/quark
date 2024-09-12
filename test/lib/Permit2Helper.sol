// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

interface Permit2 {
    function permit(address owner, Permit2Helper.PermitSingle memory permitSingle, bytes calldata signature) external;
    /// @dev Indexed in the order of token owner address, token address, spender address
    /// @dev Returns `PackedAllowance`, but we read as uint256 for testing purposes
    function allowance(address, address, address) external view returns (uint256);
}

library Permit2Helper {
    /// @notice The saved permissions
    /// @dev This info is saved per owner, per token, per spender and all signed over in the permit message
    /// @dev Setting amount to type(uint160).max sets an unlimited approval
    struct PackedAllowance {
        // amount allowed
        uint160 amount;
        // permission expiry
        uint48 expiration;
        // an incrementing value indexed per owner,token,and spender for each signature
        uint48 nonce;
    }

    /// @notice The permit data for a token
    struct PermitDetails {
        // ERC20 token address
        address token;
        // the maximum amount allowed to spend
        uint160 amount;
        // timestamp at which a spender's token allowances become invalid
        uint48 expiration;
        // an incrementing value indexed per owner,token,and spender for each signature
        uint48 nonce;
    }

    /// @notice The permit message signed for a single token allowance
    struct PermitSingle {
        // the permit data for a single token alownce
        PermitDetails details;
        // address permissioned on the allowed tokens
        address spender;
        // deadline on the permit signature
        uint256 sigDeadline;
    }

    bytes32 private constant _HASHED_NAME = keccak256("Permit2");

    bytes32 private constant _TYPE_HASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    bytes32 public constant _PERMIT_DETAILS_TYPEHASH =
        keccak256("PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)");

    bytes32 public constant _PERMIT_SINGLE_TYPEHASH = keccak256(
        "PermitSingle(PermitDetails details,address spender,uint256 sigDeadline)PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"
    );

    /// @notice Returns the domain separator for the current chain.
    function DOMAIN_SEPARATOR(address permit2Address) public view returns (bytes32) {
        return keccak256(abi.encode(_TYPE_HASH, _HASHED_NAME, block.chainid, permit2Address));
    }

    /// @notice Creates an EIP-712 typed data hash
    function _hashTypedData(bytes32 dataHash, bytes32 domainSeparator) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, dataHash));
    }

    function hash(PermitSingle memory permitSingle) internal pure returns (bytes32) {
        bytes32 permitHash = _hashPermitDetails(permitSingle.details);
        return
            keccak256(abi.encode(_PERMIT_SINGLE_TYPEHASH, permitHash, permitSingle.spender, permitSingle.sigDeadline));
    }

    function _hashPermitDetails(PermitDetails memory details) private pure returns (bytes32) {
        return keccak256(abi.encode(_PERMIT_DETAILS_TYPEHASH, details));
    }
}
