object "QuarkKafka" {

 
  code {
    let sz := datasize("QuarkKafka_deployed")
    datacopy(0, dataoffset("QuarkKafka_deployed"), sz)
    let relayer := caller()
    mstore(sz, caller()) // relayer
    codecopy(add(sz, 0x20), sub(codesize(), 0x20), 0x20) // owner
    let owner := mload(add(sz, 0x20))

    sstore(0x46ce4d9fc828e2af4f167362c7c43e310c76adc313cd8fe11e785726f972b4f6, relayer) // keccak("org.quark.relayer")
    sstore(0x3bb5ebf00f3b539fbe3d28370e5631dd2bb9520dffcea6daf564f94582db8111, owner)  // keccak("org.quark.owner")

    return(0, add(sz, 0x40))
  }
  
  object "QuarkKafka_deployed" {
    code {
      codecopy(0, sub(codesize(), 0x40), 0x40)
      let relayer := mload(0x00)
      let owner := mload(0x20)

      if and(eq(caller(), relayer), eq(shr(224, calldataload(0)), 0x2b68b9c6)) { // destruct()
        sstore(0x46ce4d9fc828e2af4f167362c7c43e310c76adc313cd8fe11e785726f972b4f6, 0) // keccak("org.quark.relayer")
        sstore(0x3bb5ebf00f3b539fbe3d28370e5631dd2bb9520dffcea6daf564f94582db8111, 0)  // keccak("org.quark.owner")

        verbatim_1i_0o(hex"ff", owner) // TODO: This "stops", right?
      }

      mstore(0x00, shl(224 /* 256 - (4*8) */, 0x665f1079)) // readQuarkCodeAddress()
      let succ0 := call(gas(), relayer, 0, 0x00, 0x04, 0, 32)
      if iszero(succ0) {
        mstore(0x00, shl(224 /* 256 - (4*8) */, 0xf16ec69c)) // ReadQuarkError()
        revert(0, 4)
      }
      let quark_code_address := mload(0x00)
      calldatacopy(0, 0, calldatasize())
      // TODO: Consider `extcodesize` and reverting if it's 0
      let succ1 := delegatecall(gas(), quark_code_address, 0x00, calldatasize(), 0, 0)
      returndatacopy(0, 0, returndatasize())

      if iszero(succ1) {
        revert(0, returndatasize())
      }

      return(0, returndatasize())
    }
  }
}
