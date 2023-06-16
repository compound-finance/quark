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

    function run(bytes memory quarkCode, bytes memory quarkCalldata) public payable returns (bytes memory) {
        QuarkVm.VmCall memory vmCall = QuarkVm.VmCall({
            vmCode: quarkCode,
            vmCalldata: quarkCalldata
        });
        bytes memory encCall = abi.encodeCall(quarkVm.run, (vmCall));
        QuarkVm quarkVm_ = quarkVm;

        (bool callSuccess, bytes memory res) = address(quarkVm_).delegatecall(encCall);
        if (!callSuccess) {
            assembly {
                revert(add(res, 32), mload(res))
            }
        }
        return res;
    }
}
