object "Manifest" {
  code {
    log2(0, 0, 0xEEB, address())
    mstore(0x00, shl(224 /* 256 - (4*8) */, 0xec2a8bb0)) // readManifest()
    let succ0 := call(gas(), caller(), 0, 0x00, 0x04, 0, 32)
    if iszero(succ0) {
      mstore(0x00, shl(224 /* 256 - (4*8) */, 0xf42df3b4)) // ReadManifestError()
      revert(0, 4)
    }
    let manifest_code_address := mload(0x00)
    let init_code_size := extcodesize(manifest_code_address)
    if eq(init_code_size, 0) {
      mstore(0x00, shl(224 /* 256 - (4*8) */, 0x2f635e4e)) // EmptyManifestError()
      revert(0, 4)
    }
    let succ1 := delegatecall(gas(), manifest_code_address, 0x00, calldatasize(), 0, 0)
    returndatacopy(0, 0, returndatasize())

    if iszero(succ1) {
      revert(0, returndatasize())
    }

    return(0, returndatasize())
  }
}
