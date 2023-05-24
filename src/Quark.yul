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

        function lte(a, b) -> r {
          r := iszero(gt(a, b))
        }

        function gte(a, b) -> r {
          r := iszero(lt(a, b))
        }

        function opcode_ex_bytes(opcode) -> sz {
          /** Returns an extra data associated with this opcode.
            * Specifiy, opcodes like PUSH1 are written in the EVM
            * assembly code as [PUSH1, x] so the opcode is two-bytes
            * wide (instead of most operations being one-byte wide). For
            * PUSH2, it's three-bytes wide. As such, we need to be able
            * to skip over the extra bytes when walking the opcodes. This
            * function makes it easy to know what should be skipped.
          */
          sz := 0
          if and(gte(opcode, 0x60), lte(opcode, 0x7F)) {
            // PUSHX
            sz := add(1, sub(opcode, 0x60)) // PUSH1 is 1 extra byte, PUSH2 is 2 extra bytes, etc.
          }
        }

        function is_jump(opcode) -> res {
          /** Simple function to check if the operation is a jump and needs
            * to have the operand offset.
          */
          res := or(eq(opcode, 0x56), eq(opcode, 0x57)) // JUMP or JUMPI
        }

        function load_byte_at(ptr, i) -> b {
          /** We don't have granularity in the EVM to read at
            * specific bytes, only at 32-byte words. Thus, if we have something
            * like 0x1122334455... and we want to load the second byte, we
            * must mload the entire word, shift right to get the correct byte
            * to the right-most position and then mask it out with 0x000000...FF.
            * This is what this function purports to do.
            */
          let word_idx := div(i, 32)
          let offset := sub(i, mul(word_idx, 32))
          let word_ptr := add(ptr, word_idx)
          let word := mload(word_ptr)
          b := and(shr(word, mul(offset, 8)), 0xFF)
        }

        function store_byte_at(ptr, i, v) {
          /** We don't have granularity in the EVM to read and write at
            * specific bytes, only at 32-byte words. Thus, if we have something
            * like 0x1122334455... and we want to change the second byte, we
            * must mload the entire word, bitmask out the second-highest byte and
            * `or` in the new byte and then mstore the new value. That's what this
            * function purports to do.
            */
          let word_idx := div(i, 32)
          let offset := sub(i, mul(word_idx, 32))
          let word_ptr := add(ptr, word_idx)
          let current_word := mload(word_ptr)
          let bitmask := not(shl(0xFF, mul(offset, 8)))
          let shifted_v := shl(v, mul(offset, 8))
          let r := or(and(current_word, bitmask), shifted_v)
          mstore(word_ptr, r)
        }

        function rewrite(src, sz, dst, offset) -> dst_sz {
          /** This is the crux of rewriting our contract code
            * to allow an offset in position. This is a problem because jumps
            * in the EVM are absolute, not relative. Thus if there's code that
            * looks like:
            *
            * 000: CALLVALUE
            * 001: PUSH1 05
            * 003: JUMPI
            * 004: REVERT
            * 005: JUMPDEST
            *
            * But we want to prepend some code in front of it, it would become:
            *
            * 000: PUSH1 55  // New code
            * 002: LOG       // New code
            * 003: CALLVALUE // Original code, shifted
            * 004: PUSH1 05
            * 006: JUMPI     // OH NO!!
            * 007: REVERT
            * 008: JUMPDEST
            *
            * But that's a huge problem because our jump instruction is still
            * trying to jump to 003 but it really meant to jump to 008 since
            * everything was shifted by 3 bytes in the PC. To remedy this situation
            * we can automatically rewrite the contract as such:
            *
            * 000: PUSH1 55  // New code
            * 002: LOG       // New code
            * 003: CALLVALUE // Original code
            * 004: PUSH1 05
            * 006: PUSH1 06  // <-- INSERTED CODE
            * 008: ADD       // <-- INSERTED CODE
            * 009: JUMPI
            * 00A: REVERT
            * 00B: JUMPDEST
            *
            * That is, before an JUMP or JUMPI, we need to add a `PUSH offset; ADD` which tracks an offset from the original
            * source code and adds that to whatever the dst of the JUMP was going to be. To make it even more frustrating, each
            * time we add that code, we push the offset back even further (more code!) and thus we need to keep a running tally.
            *
            * This is pretty insane, but there's no reason it shouldn't work in the general case and doesn't rely on any tricks.
            */
          for { let i := 0 } lt(i, sz) { i := add(i, 1) }
          {
            // Get the current opcode from the src as we walk it
            let opcode := load_byte_at(src, i)
            let is_jmp := is_jump(opcode)

            // TODO: we need to figure out the *best* PUSH instruction based on offset-- right now we're using PUSH1 so it only works for a small script

            // If this isn't a JUMP, we don't need to do anything, just keep walking
            if is_jmp {
              // These are the two instructions we'll need to add: [PUSH2, offset, ADD]
              // TODO: Allow PUSH2, etc
              let push_opcode := 0x60 // `PUSH1`
              let push_value := add(offset, 3) // We need to account for the size of this change, as well!
              let add_opcode := 0x60 // `ADD`

              store_byte_at(dst, add(i, offset), push_opcode)
              offset := add(offset, 1)
              store_byte_at(dst, add(i, offset), push_value)
              offset := add(offset, 1)
              store_byte_at(dst, add(i, offset), add_opcode)
              offset := add(offset, 1)
            }

            // Skip over any data bytes, leaving them alone
            let extra_bytes := opcode_ex_bytes(opcode)
            i := add(i, extra_bytes)
          }

          dst_sz := add(sz, offset)
        }

        function breakpoint(i) {
          /** YUL to call a Forge breakpoint.
            *
            * for a, use i = 0 
            * for b, use i = 1, ...
            */
          // breakpoint(string)
          let sig := 0xf0259e92

          let callbytes := allocate(0x80)
          mstore(add(callbytes, 0), sig) // sig
          mstore(add(callbytes, 1), 0x20) // offset
          mstore(add(callbytes, 2), 1) // len
          mstore(add(callbytes, 3), shl(add(0x61, i), 31)) // 'a' + i
          let callbytes_offset := add(callbytes, 28) // skip the first 28 bytes since we start directly with the 4-byte sig
          let callbytes_len := add(4, mul(3, 32)) // 3 words + 4 bytes
          pop(call(gas(), 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D, 0, callbytes_offset, callbytes_len, 0, 0))
        }

        // Call back to the Relayer contract (who is the caller) to get the Quark code
        // TODO: Check for reverts
        pop(call(gas(), caller(), 0, 0, 0, 0, 0))

        // Read the return data from the Relayer
        let quark_size := returndatasize()
        let quark_offset := allocate(quark_size)
        returndatacopy(quark_offset, 0, quark_size)

        breakpoint(1) // 'b'

        // Next, we need to prepend our data and rewrite the script with the new offset
        let quark_final := allocate(mul(quark_size, 5)) // This is an overestimate to how large the new script could possibly be!
        let quark_final_sz := rewrite(quark_offset, quark_size, quark_final, 0) // TODO: Prepend

        // Boy howdy, need to see how this works!!!

        // Return the Quark data
        return(quark_final, quark_final_sz)
      }
    }
  }
}
