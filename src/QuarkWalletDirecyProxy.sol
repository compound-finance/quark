// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

interface Impl {
  function myFun(address signer, address executor, bytes calldata userdata) external;
}

contract QuarkWalletDirectProxy {
  address immutable impl;
  address immutable signer;
  address immutable executor;
  constructor(address impl_, address signer_, address executor_) {
    impl = impl_;
    signer = signer_;
    executor = executor_;
  }

  fallback(bytes calldata userdata) external payable returns (bytes memory) {
    impl.delegatecall(abi.encodeCall(Impl.myFun, (signer, executor, userdata)));
    return hex"";
  }
}


