object "QuarkWalletDirectProxy" {
  // This is the constructor code of the contract.
  code {
    function mstore20(dest, addr) {
      for { let i := 0 } lt(i, 20) { i := add(i, 1) } {
        mstore8(add(dest, i), and(addr, shl(0xff, sub(20, i))))
      }
    }

    if not(eq(calldatasize(), 0x60)) {
      revert(0, 0)
    }

    calldatacopy(0x00, 0x00, 0x60)
    let signer := mload(0x00)
    let executor := mload(0x20)
    let impl := mload(0x40)

    datacopy(0x00, dataoffset("QuarkWalletDirectProxy_deployed"), datasize("QuarkWalletDirectProxy_deployed"))
    mstore20(0x04, signer)
    mstore20(0x24, executor)
    mstore20(0x44, impl)
    return(0x00, datasize("QuarkWalletDirectProxy_deployed"))
  }

  object "QuarkWalletDirectProxy_deployed" {
    code {
      let signer := verbatim_0i_1o(hex"730000000000000000000000000000000000000000")
      let executor := verbatim_0i_1o(hex"730000000000000000000000000000000000000000")
      let impl := verbatim_0i_1o(hex"730000000000000000000000000000000000000000")

      function returnUint(v) {
        mstore(0, v)
        return(0, 0x20)
      }

      function selector() -> s {
        s := div(calldataload(0), 0x100000000000000000000000000000000000000000000000000000000)
      }

      switch selector()
      case 0x238ac933 /* "signer()" */ {
          returnUint(signer)
      }
      case 0xc34c08e5 /* "executor()" */ {
          returnUint(executor)
      }
      default {
        let calldataLen := calldatasize()
        calldatacopy(0, 0, calldataLen)
        pop(delegatecall(gas(), impl, 0x00, calldataLen, 0x00, 0x00))
      }
    }
  }
}