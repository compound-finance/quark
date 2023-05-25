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

      function revert_err(offset, size) {
        datacopy(0, offset, size)
        revert(0, size)
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

          // Clear the quark code (to reclaim gas)
          clear_quark(quark_size)

          breakpoint(0)

          // Ensure the contract was created, and if not, bail
          if iszero(extcodesize(virt)) {
            revert_err(dataoffset("Create2Failed"), datasize("Create2Failed"))
          }

          // Invoke the newly deployed virtual contract (i.e. run the user-supplied code)
          let succ := call(gas(), virt, 0, 0, 0, 0, 0)

          if iszero(succ) {
            revert_err(dataoffset("InvocationFailure"), datasize("InvocationFailure"))
          }

          // Self-destruct the Virtual contract by calling it again
          succ := call(gas(), virt, 0, 0, 0, 0, 0)

          if iszero(succ) {
            revert_err(dataoffset("CleanupFailure"), datasize("CleanupFailure"))
          }

          // We don't return any meaningful value,
          // though we could pass back the result
          // of the function call.
          return(0, 0)
        }
      }
    }

    data "Create2Failed" hex"0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000e43726561746532206661696c6564000000000000000000000000000000000000"
    data "InvocationFailure" hex"0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000001b436f6e747261637420496e766f636174696f6e204661696c7572650000000000"
    data "CleanupFailure" hex"00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000018436f6e747261637420436c65616e7570204661696c7572650000000000000000"

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

        function rewrite_push_3(op_idx, v) {
          mstore8(add(op_idx, 1), byte(29, v))
          mstore8(add(op_idx, 2), byte(30, v))
          mstore8(add(op_idx, 3), byte(31, v))
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
        let succ := call(gas(), caller(), 0, 0, 0, 0, 0)

        if iszero(succ) {
          // This is an unexpected failure
          revert(0, 0)
        }

        let appendix_size := datasize("Appendix")

        // Read the return data from the Relayer
        let quark_size := returndatasize()
        let total_size := add(quark_size, appendix_size)
        let quark_offset := allocate(total_size)
        returndatacopy(quark_offset, 0, quark_size)

        // TODO: Possibly check quark begins with magic incantation

        // Load the caller from construction parameters
        let account_idx := allocate(32)
        datacopy(account_idx, datasize("Virtual"), 32)
        let account := mload(account_idx)

        // This is overwriting the magic number!
        datacopy(quark_offset, dataoffset("Prependix"), datasize("Prependix"))

        let appendix_jump_dst := add(quark_size, 1)

        // Set the JUMP3 value, byte by byte
        // Note: might want to check this fits in 3-bytes!
        rewrite_push_3(quark_offset, appendix_jump_dst)

        let appendix_offset := add(quark_offset, quark_size)

        // Write the appendix
        datacopy(appendix_offset, dataoffset("Appendix"), datasize("Appendix"))

        // Rewrite our one jump in the appendix
        rewrite_push_3(add(appendix_offset, 0x5), add(quark_size, 0x12))

        // Storage: 0=account, 1=relayer, 2=called
        log1(0, 0, account)
        sstore(0, account)
        sstore(1, caller())

        // Return the Quark data
        return(quark_offset, total_size)
      }

      /*
       * 000: PUSH3 XXX // Appendix index
       * 004: JUMP
       * 005: JUMPDEST
       */
      data "Prependix" hex"62000000565B"

      /*
       * 000: fe       [INVALID]
       * 001: 5b       [JUMPDEST]
       * 002: 6002     [PUSH1 2]
       * 004: 54       [SLOAD]     // sload(2)
       * 005: 62000000 [PUSH3 XXX]
       * 009: 57       [JUMPI]
       * 00a: 6001     [PUSH1 1]   // we haven't been called
       * 00c: 6002     [PUSH1 2]
       * 00e: 55       [SSTORE]    // sstore(2, 1)
       * 00f: 6005     [PUSH1 5]
       * 011: 56       [JUMP]      // return to user code
       * 012: 5b       [JUMPDEST]  // we've been called before, blow up!
       * 013: 6000     [PUSH1 0]
       * 015: 54       [SLOAD]     // sload(0)
       * 016: ff       [SELFDESTRUCT]
       */
      data "Appendix" hex"fe5b600254620000005760016002556005565b600054ff"
    }
  }
}
