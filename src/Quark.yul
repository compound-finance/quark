object "Quark" {
  code {
    datacopy(0, dataoffset("Relayer"), datasize("Relayer"))
    return(0, datasize("Relayer"))
  }
  object "Relayer" {
    // Return the calldata
    // code {
      // TODO: Deploy Virtual contract with 
    //  mstore(0x80, calldataload(0))
    //  return(0x80, calldatasize())
    //}

    code {
      function allocate(size) -> ptr {
          ptr := mload(0x40)
          // Note that Solidity generated IR code reserves memory offset ``0x60`` as well, but a pure Yul object is free to use memory as it chooses.
          if iszero(ptr) { ptr := 0x60 }
          mstore(0x40, add(ptr, size))
      }

      // first create "Virtual"
      let size := datasize("Virtual")
      let offset := allocate(size)
      // This will turn into codecopy for EVM
      datacopy(offset, dataoffset("Virtual"), size)
      // constructor parameter is calldata itself
      mstore(add(offset, size), calldataload(0))
      // create the virtual contract
      let virt := create(offset, calldatasize(), 0)

      // invoke the virtual contract
      pop(call(gas(), virt, 0, 0, 0, 0, 0))

      // todo: self destruct the contract
    }

    object "Virtual" {
      code {
        // Deploy just the runtime code itself
        mstore(0x80, calldataload(0))

        // TODO: Handle allowing for self destruct (!)
        return(0x80, calldatasize())
      }
    }
  }
}
