object "Quark" {
  code {
    datacopy(0, dataoffset("Relayer"), datasize("Relayer"))
    return(0, datasize("Relayer"))
  }
  object "Relayer" {
    code {
      /**
        * First, we'll check if we're inside a Quark,
        *  - If yes, we'll return the current Quark code
        *  - If no, we'll run a new Quark execution
        *
        * This has the added benefit of preventing re-entry, though
        * we could soften this req. in the future.
        */

      function running_quark() -> running {
        /** Returns if we're inside a quark,
          * which is defined as having the
          * quark size stored at storage slot 0.
          */
        running := gt(sload(0), 0)
      }

      function allocate(size) -> ptr {
        /** Allocates memory in a safe way. Returns a pointer to it.
          */
          ptr := mload(0x40)
          if iszero(ptr) { ptr := 0x60 }
          mstore(0x40, add(ptr, size))
      }

      function word_count(sz) -> words {
        /** This is 32-byte word count [rounding up]. For example,
          * word_count(5) == 1
          * word_count(32) == 1
          * word_count(33) == 2
          */
        words := div(sz, 32)
        if lt(mul(words, 32), sz) {
          words := add(words, 1)
        }
      }

      function load_quark() -> offset, quark_size {
        /** Loads the current quark from storage.
          * We store the quark size (in words) at
          * storage slot 0, and then the quark code
          * at storage slot 1+. This reassembles that
          * code into memory.
          */

        quark_size := sload(0)
        offset := allocate(quark_size)
        let quark_words := word_count(quark_size)
        for { let i := 0 } lt(i, quark_words) { i := add(i, 1) }
        {
          mstore(add(offset, mul(i, 32)), sload(add(i, 1)))
        }
      }

      function store_quark(offset, quark_size) {
        /** Stores a quark from memory into storage.
          * See `load_quark` for more information.
          */

        sstore(0, quark_size)
        let quark_words := word_count(quark_size)
        for { let i := 0 } lt(i, quark_words) { i := add(i, 1) }
        {
          let word := mload(add(offset, mul(i, 32)))
          sstore(add(i, 1), word)
        }
      }

      function clear_quark(quark_size) {
        /** Clear quark from storage, reclaiming
          * gas since we zero out data in same trx.
          */

        let quark_words := word_count(quark_size)
        for { let i := 0 } lt(i, quark_words) { i := add(i, 1) }
        {
          sstore(add(i, 1), 0)
        }
        sstore(0, 0)
      }

      switch running_quark()
      case true {
        /** If we're in a running quark, simply return
          * the code for the quark.

          * Note: this is used by the Virtual contract
          *       below to get the quark data since we
          *       can't pass it to Virtual since it would
          *       change the data passed to `create2` and
          *       thus change the created contract address
          *       each time.
          */
        let offset, size := load_quark()
        return(offset, size)
      }
      case false {
        /** Start a new quark environment.
          * First, we'll store the quark data in storage (to make
          * it available for the Virtual contract's init code).
          *
          * Next, we'll deploy (via create2) the Virtual contract,
          * which will call back into this contract to get the init
          * code for that contract (and return it directly).
          *
          * Finally, we'll clean up storage and get the Virtual
          * contract to self destruct.
          */

        // Store the quark code
        let quark_size := calldatasize()
        let quark_offset := allocate(quark_size)
        calldatacopy(quark_offset, 0, quark_size)
        store_quark(quark_offset, quark_size)

        // Load the Virtual contract data
        let virt_size := datasize("Virtual")
        let virt_offset := allocate(virt_size)
        datacopy(virt_offset, dataoffset("Virtual"), virt_size)

        // Deploy the Virtual contract
        let virt := create2(0, virt_offset, virt_size, 0)

        // Invoke the newly deployed virtual contract (i.e. run the user-supplied code)
        pop(call(gas(), virt, 0, 0, 0, 0, 0))

        // Self-destruct the Virtual contract
        // TODO

        // Clear the quark code (to reclaim gas)
        clear_quark(quark_size)
      }
    }

    object "Virtual" {
      code {
        function allocate(size) -> ptr {
            ptr := mload(0x40)
            if iszero(ptr) { ptr := 0x60 }
            mstore(0x40, add(ptr, size))
        }

        // TODO: Double check this doesn't revert?
        pop(call(gas(), caller(), 0, 0, 0, 0, 0))

        let ctx_size := returndatasize()
        let ctx_offset := allocate(ctx_size)
        returndatacopy(ctx_offset, 0, ctx_size)

        return(ctx_offset, ctx_size)
      }
    }
  }
}
