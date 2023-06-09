// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./QuarkVm.sol";

contract QuarkVmWallet {
    error Unauthorized();

    QuarkVm immutable quarkVm;
    address immutable owner;
    address immutable relayer;

    uint256 quarkSize;
    mapping(uint256 => bytes32) quarkChunks;

    constructor(QuarkVm quarkVm_, address owner_) {
        quarkVm = quarkVm_;
        owner = owner_;
        relayer = msg.sender;

        assembly {
            sstore(0x46ce4d9fc828e2af4f167362c7c43e310c76adc313cd8fe11e785726f972b4f6, caller()) // keccak("org.quark.relayer")
            sstore(0x3bb5ebf00f3b539fbe3d28370e5631dd2bb9520dffcea6daf564f94582db8111, owner_)   // keccak("org.quark.owner")
        }
    }

    function readQuark() internal view returns (bytes memory) {
        bytes memory quark = new bytes(quarkSize);
        uint256 chunks = wordSize(quarkSize);
        for (uint256 i = 0; i < chunks; i++) {
            bytes32 chunk = quarkChunks[i];
            assembly {
                // TODO: Is there an easy way to do this in Solidity?
                // Note: the last one can overrun the size, should we prevent that?
                mstore(add(quark, add(32, mul(i, 32))), chunk)
            }
        }
        return quark;
    }

    // TODO: Can we make this calldata
    function setQuark(bytes memory quark) external {
        if (msg.sender != relayer && msg.sender != owner) {
            revert Unauthorized();
        }

        quarkSize = quark.length;
        uint256 chunks = wordSize(quarkSize);
        for (uint256 i = 0; i < chunks; i++) {
            bytes32 chunk;
            assembly {
                // TODO: Is there an easy way to do this in Solidity?
                chunk := mload(add(quark, add(32, mul(i, 32))))
            }
            quarkChunks[i] = chunk;
        }
    }

    // Clears quark data a) to save gas costs, and b) so another quark can
    // be run for the same quarkAddress in the future.
    function clearQuark() external {
        if (msg.sender != relayer && msg.sender != owner) {
            revert Unauthorized();
        }

        uint256 chunks = wordSize(quarkSize);
        for (uint256 i = 0; i < chunks; i++) {
            quarkChunks[i] = 0;
        }
        quarkSize = 0;
    }

    // wordSize returns the number of 32-byte words required to store a given value.
    // E.g. wordSize(0) = 0, wordSize(10) = 1, wordSize(32) = 1, wordSize(33) = 2
    function wordSize(uint256 x) internal pure returns (uint256) {
        uint256 r = x / 32;
        if (r * 32 < x) {
            return r + 1;
        } else {
            return r;
        }
    }

    function run_(bytes memory quarkCalldata) internal returns (bytes memory) {
        QuarkVm.VmCall memory vmCall = QuarkVm.VmCall({
            vmCode: readQuark(),
            vmCalldata: quarkCalldata
        });
        bytes memory encCall = abi.encodeCall(quarkVm.run, (vmCall));
        QuarkVm quarkVm_ = quarkVm;
        bool res;
        uint256 retSize;
        assembly {
            res := delegatecall(gas(), quarkVm_, add(encCall, 0x20), mload(encCall), 0, 0)
            retSize := returndatasize()
        }
        bytes memory returnData = new bytes(retSize);
        assembly {
            returndatacopy(add(returnData, 0x20), 0, retSize)
            if iszero(res) {
                revert(add(returnData, 0x20), retSize)
            }
        }
        return returnData;
    }

    fallback(bytes calldata quarkCalldata) external payable returns (bytes memory) {
        run_(quarkCalldata);
    }

    /***
     * @notice Revert given empty call.
     */
    receive() external payable {
        run_(hex"");
    }
}
