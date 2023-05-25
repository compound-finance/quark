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

      // TODO: We should consider making this specific to a caller, but
      //       alternatively, we could enforce that caller must be an EOA to
      //       prevent having to think too hard about this.

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

      function breakpoint(i) {
        /** YUL to call a Forge breakpoint.
          *
          * for a, use i = 0 
          * for b, use i = 1, ...
          */

        // sig for `breakpoint(string)`
        let sig := 0xf0259e92

        let callbytes := allocate(0x64)
        mstore(add(callbytes, 0x00), shl(mul(28, 8), sig))          // 0x00: sig
        mstore(add(callbytes, 0x04), 0x20)                          // 0x04: offset
        mstore(add(callbytes, 0x24), 1)                             // 0x24: len
        mstore(add(callbytes, 0x44), shl(mul(31, 8), add(0x61, i))) // 0x44: 'a' + i

        pop(call(gas(), 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D, 0, callbytes, 0x64, 0, 0))
      }

      function selector() -> s {
        s := div(calldataload(0), 0x100000000000000000000000000000000000000000000000000000000)
      }

      function decode_as_address(offset) -> v {
        v := decode_as_uint(offset)
        if iszero(iszero(and(v, not(0xffffffffffffffffffffffffffffffffffffffff)))) {
          revert(0, 0)
        }
      }
      
      function decode_as_uint(offset) -> v {
        let pos := add(4, mul(offset, 0x20))
        if lt(calldatasize(), add(pos, 0x20)) {
            revert(0, 0)
        }
        v := calldataload(pos)
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
        /** First check for some helpful function calls. These are guaranteed to be invalid bytecode
          * as they all must start with 0xfe which is the "invalid" code.
          */

        switch selector()
        case 0xfe5a936a /* "quarkAddress25(address)(address)" */ {
          // Note: we can share this code if we want, but I'd rather copy it

          // Track the caller (TODO: Take this as an arg?)
          let account := decode_as_address(0)

          // Load the Virtual contract data
          let virt_size := datasize("Virtual")
          let virt_offset := allocate(add(virt_size, 32))
          datacopy(virt_offset, dataoffset("Virtual"), virt_size)

          // Add the caller to the init code [Note: we *want* this to be part of the create2 derivation path]
          mstore(add(virt_offset, virt_size), account)

          let code_hash := keccak256(virt_offset, add(virt_size, 32))

          // keccak256( 0xff ++ address ++ salt ++ keccak256(init_code))[12:]

          // 0x01 + 0x14 + 0x20 + 0x20 = 0x55
          let derivation := allocate(0x55)
          mstore8(derivation, 0xFF)                           // 00-01: 0xFF
          mstore(add(derivation, 0x01), shl(96, address()))   // 01-15: {address}
          mstore(add(derivation, 0x15), 0)                    // 15-35: {salt}
          mstore(add(derivation, 0x35), code_hash)            // 35-55: {sha3(init)}

          let addr := and(keccak256(derivation, 0x55), 0xffffffffffffffffffffffffffffffffffffffff)

          let res := allocate(32)
          mstore(res, addr)

          return(res, 32)
        }
        case 0xfee6f038 /* "virtualCode81()(bytes)" */ {
          // Load the Virtual contract data
          let virt_size := datasize("Virtual")
          let virt_offset := allocate(add(virt_size, 64))

          mstore(virt_offset, 0x20)
          mstore(add(virt_offset, 32), virt_size)
          datacopy(add(virt_offset, 64), dataoffset("Virtual"), virt_size)

          return(virt_offset, add(virt_size, 64))
        }
        default {
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

          // Track the caller
          let account := caller()

          // Store the quark code
          let quark_size := calldatasize()
          let quark_offset := allocate(quark_size)
          calldatacopy(quark_offset, 0, quark_size)
          store_quark(quark_offset, quark_size)

          // Load the Virtual contract data
          let virt_size := datasize("Virtual")
          let virt_offset := allocate(add(virt_size, 32))
          datacopy(virt_offset, dataoffset("Virtual"), virt_size)

          // Add the caller to the init code [Note: we *want* this to be part of the create2 derivation path]
          mstore(add(virt_offset, virt_size), account)

          log1(virt_offset, add(virt_size, 32), 0xdeadbeef)

          // Deploy the Virtual contract
          let virt := create2(0, virt_offset, add(virt_size, 32), 0)

          // Ensure the contract was created, and if not, bail
          if iszero(extcodesize(virt)) {
            revert(0, 0)
          }

          // Invoke the newly deployed virtual contract (i.e. run the user-supplied code)
          // TODO: Check revert
          pop(call(gas(), virt, 0, 0, 0, 0, 0))

          // Self-destruct the Virtual contract by calling it again
          pop(call(gas(), virt, 0, 0, 0, 0, 0))

          // Clear the quark code (to reclaim gas)
          clear_quark(quark_size)

          // We don't return any meaningful value,
          // though we could pass back the result
          // of the function call.
          return(0, 0)
        }
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
          b := byte(0, mload(add(ptr, i)))
        }

        function store_byte_at(ptr, i, v) {
          /** We don't have granularity in the EVM to read and write at
            * specific bytes, only at 32-byte words. Thus, if we have something
            * like 0x1122334455... and we want to change the second byte, we
            * must mload the entire word, bitmask out the second-highest byte and
            * `or` in the new byte and then mstore the new value. That's what this
            * function purports to do.
            */
          mstore8(add(ptr, i), v)
        }

        function byte_count(v) -> c {
          /** Returns the smallest number of bytes that can fit c
            * byte_count(0) -> 0
            * byte_count(100) -> 1
            * byte_count(1000) -> 2
            */
          c := 0
          for {} gt(v, 0) {}
          {
            c := add(c, 1)
            v := shr(8, v)
          }
        }

        function rewrite(src, sz, dst, offset) -> dst_sz {
          breakpoint(0)
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
            * source code and adds that to whatever the dst of the JUMP was going to be. This feels almost right, but it
            * doesn't work because if you're jumping backwards, then you might have:
            *
            * 000: PUSH1 55  // New code
            * 002: LOG       // New code
            * 003: CALLVALUE // Original code
            * 004: JUMPDEST
            * 004: PUSH1 04
            * 006: PUSH1 06  // <-- INSERTED CODE
            * 008: ADD       // <-- INSERTED CODE
            * 009: JUMPI
            * 00A: REVERT
            *
            * The JUMPDEST is behind you. Now, we could realize that 99% of JUMPs are of the form:
            * `PUSH X; JUMP` and rewrite those to `PUSH X+OFFSET; JUMP` which would beget two new
            * issues: a) what do we do if there's not a PUSH X before a jump, but also b) what if
            * we overflow the PUSH command, e.g. from a PUSH1 that now needs to be a PUSH2, which
            * would lead us right back to needing to have dynamic offsets and the problem above.
            *
            * There is one solution that should work both for dynamic jumps, forward and backward
            * jumps, and everything else that is elegant but also complex: a static analysis jump
            * table. Here, we store a mapping of where each JUMPDEST moved to from the src to the
            * dst and then we (at runtime) have a mapping s.t. each jump goes to the new JUMPDEST.
            * We could store this literally as a table, e.g.
            *
            * Jump Table [Logical]
            * 005 -> 01d
            *
            * This table says that the JUMPDEST at 005 should now map to 00B.
            * We can then rewrite all JUMP and JUMPI instructions to pull
            * from this table. The easiest way is to write the table as a
            * code segment and change JUMP to `JUMP[I] {jump table fn}`,
            * and the argument `dst` will be consumed by the function,
            * correctly jumping to the correct new dst. Here's sample code:
            *
            * 000: PUSH1 55  // New code
            * 002: LOG       // New code
            * 003: JUMPDEST  // [Start of jump table]
            * 004: DUP1 
            * 005: PUSH1 005 // entry0.src
            * 007: EQ
            * 008: PUSH1 01d // entry0.dst
            * 00a: SWAP1
            * 00b: PUSH1 012
            * 00d: JUMPI
            * 00e: POP
            * 00f: PUSH1 000 // [Default case - Error]
            * 011: JUMP      
            * 012: JUMPDEST  // [Success case]
            * 013: SWAP      //
            * 014: POP
            * 015: JUMP 
            * 016: CALLVALUE // Original code
            * 017: PUSH1 005
            * 019: PUSH1 003 // INSERTED CODE -- go to jump table
            * 01b: JUMPI
            * 01c: REVERT
            * 01d: JUMPDEST
            *
            * This is significantly more complex than the other approaches, but it is
            * completely safe, even if the code, for instance, had `PUSH1 004; PUSH1 001; ADD; JUMPI`.
            * That is, other than the potential increase in gas cost, the code should have the identical
            * effect of the unmodified code. The complex part is that we need to walk the
            * code twice. First to collect JUMPDEST instructions once, and then a second time
            * to actually write the complete program.
            */
          for { let i := 0 } lt(i, sz) { i := add(i, 1) }
          {
            // Get the current opcode from the src as we walk it
            let opcode := load_byte_at(src, i)
            let is_jmp := is_jump(opcode)

            // We're just going to use PUSH3 since it should be suffiently large-- also it sticks out like a sore thumb

            // If this isn't a JUMP, we don't need to do anything, just keep walking
            if is_jmp {
              breakpoint(1)

              let push_value := add(offset, 5) // We need to account for the size of this change, as well! [PUSH3, x_0, x_1, x_2, ADD]

              // These are the two instructions we'll need to add: [PUSH3, offset, ADD]
              let push_opcode := 0x62 // `PUSH3`
              let add_opcode := 0x01 // `ADD`

              store_byte_at(dst, add(i, offset), push_opcode)
              offset := add(offset, 1)
              store_byte_at(dst, add(i, offset), byte(29, offset))
              offset := add(offset, 1)
              store_byte_at(dst, add(i, offset), byte(30, offset))
              offset := add(offset, 1)
              store_byte_at(dst, add(i, offset), byte(31, offset))
              offset := add(offset, 1)
              store_byte_at(dst, add(i, offset), add_opcode)
              offset := add(offset, 1)
            }

            // Note/todo: we probably can just have a big "copy width" thing instead of this copy opcode and then copy data

            // Copy the opcode
            store_byte_at(dst, add(i, offset), opcode)

            // Skip over any data bytes, leaving them alone
            let extra_bytes := opcode_ex_bytes(opcode)

            // If we have extra bytes, just copy that, as well
            if gt(extra_bytes, 0) {
              let shift_amount := sub(256, mul(extra_bytes, 8))
              let extra_bytes_data := shl(shift_amount, shr(shift_amount, mload(add(add(src, i), 1)))) // Zero out excess bytes
              mstore(add(dst, add(add(i, offset), 1)), extra_bytes_data)
            }

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

          // sig for `breakpoint(string)`
          let sig := 0xf0259e92

          let callbytes := allocate(0x64)
          mstore(add(callbytes, 0x00), shl(mul(28, 8), sig))          // 0x00: sig
          mstore(add(callbytes, 0x04), 0x20)                          // 0x04: offset
          mstore(add(callbytes, 0x24), 1)                             // 0x24: len
          mstore(add(callbytes, 0x44), shl(mul(31, 8), add(0x61, i))) // 0x44: 'a' + i

          pop(call(gas(), 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D, 0, callbytes, 0x64, 0, 0))
        }

        // Call back to the Relayer contract (who is the caller) to get the Quark code
        // TODO: Check for reverts
        pop(call(gas(), caller(), 0, 0, 0, 0, 0))

        // Read the return data from the Relayer
        let quark_size := returndatasize()
        let quark_offset := allocate(quark_size)
        returndatacopy(quark_offset, 0, quark_size)

        // Load the caller from construction parameters
        let account_idx := allocate(32)
        datacopy(account_idx, datasize("Virtual"), 32)
        let account := mload(account_idx)

        let prependix_size := datasize("Prependix")

        // Next, we need to prepend our data and rewrite the script with the new offset
        let quark_final := allocate(add(add(prependix_size, 2), mul(quark_size, 5))) // This is an overestimate to how large the new script could possibly be!

        // Copy in our prependix
        datacopy(quark_final, dataoffset("Prependix"), prependix_size)
        mstore8(add(quark_final, prependix_size), 0xfe) // INVALID in case of failed jump
        mstore8(add(add(quark_final, prependix_size), 1), 0x5b) // JUMPDEST for the user code

        let prependix_total_size := add(prependix_size, 2) // account for INVALID and JUMPDEST

        // Now copy in the rest of the code
        let quark_final_sz := rewrite(quark_offset, quark_size, quark_final, prependix_total_size)

        // Boy howdy, need to see how this works. Let's write some storage and leave.

        // Storage: 0=account, 1=relayer, 2=called
        log1(0, 0, account)
        sstore(0, account)
        sstore(1, caller())

        // Return the Quark data
        return(quark_final, quark_final_sz)
      }

      object "Prependix" {
        code {
          // Check if we've already been called
          let account := sload(0)
          let relayer := sload(1)
          let called := sload(2)

          // Yes, then we're either going to self-destruct or revert
          if gt(called, 0) {
            if eq(caller(), relayer) { // This is the relayer giving us the kill signal
              selfdestruct(account) // Send back any eth to associated account
            }

            // Otherwise, prevent any callbacks to our contract (note: we could soften this restraint)
            invalid()
          }

          // This is the first run of our code, note that
          sstore(2, add(called, 1))

          // Okay, this is weird. We want to trick the compiler into jumping into the user-defined code
          // after this point. The optimizer might decide to change the layout of this function, so
          // we instead just encode a `PUSH {PrependixSize+1}; JUMP` at the end of this code path
          // and then write out a `JUMPDEST` before the user's code.
          verbatim_1i_0o(hex"56", add(datasize("Prependix"), 1))
        }
      }
    }
  }
}
