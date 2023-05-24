object "Quark" {
  code {
    /** This is the init code (constructor) for
      * the Quark Relayer contract.
      *
      * This simply returns the Relayer code below.
      */
    datacopy(0, dataoffset("Relayer"), datasize("Relayer"))
    return(0, datasize("Relayer"))
  }

  object "Relayer" {
    /** This is the core Quark Relayer contract, which
      * is what users call into (the "to" address).
      *
      * The calldata pass in calls to this function will
      * be executed as Solidity code from a pre-determined
      * address (based on create2, but not on the contract
      * code itself).
      *
      * You can call this function as many times as you like,
      * and you will execute different code *from the same address*.
      *
      * Note: do not wrap your code in any Solidity contract or ABI
      *       encoding-- it should be the raw evm code to execute.
      *
      * Note: you currently need your code to self-destruct at the end
      *       in order to clean up. We hope to remove this constraint.
      *
      * Note: self-destruct is required for this trick to work, and
      *       may later be removed according to EIP-4758.
      */

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
        // TODO: Check revert
        pop(call(gas(), virt, 0, 0, 0, 0, 0))

        // Self-destruct the Virtual contract
        // TODO

        // Clear the quark code (to reclaim gas)
        clear_quark(quark_size)

        // We don't return any meaningful value,
        // though we could pass back the result
        // of the function call.
        return(0, 0)
      }
    }

    object "Virtual" {
      /** This is the contract that is deployed (and then destructed)
        * where your Quark code will run.
        *
        * The constructor is below (there is no contract code-- that's
        * the user-spplied Quark code), so the constructor is simply
        * responsible for loading and then returning the Quark code.
        *
        * Since this is based on create2, we can't accept the Quark
        * code as input. Instead, we call back to the Relayer contract,
        * which has stored the Quark code. We simply then return that value.
        */
      code {
        function allocate(size) -> ptr {
          /** Allocates memory in a safe way. Returns a pointer to it.
          */
          ptr := mload(0x40)
          if iszero(ptr) { ptr := 0x60 }
          mstore(0x40, add(ptr, size))
        }

        // Call back to the Relayer contract to get the Quark code
        // TODO: Check revert
        pop(call(gas(), caller(), 0, 0, 0, 0, 0))

        // Read the return data from the Relayer
        let quark_size := returndatasize()
        let quark_offset := allocate(quark_size)
        returndatacopy(quark_offset, 0, quark_size)

        // Return the Quark data
        return(quark_offset, quark_size)
      }
    }
  }
}
