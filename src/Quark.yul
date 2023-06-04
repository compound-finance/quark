object "Quark" {
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
    *
    * A Quark contract should effectively look like this:
    *
    * contract Quark {
    *   address relayer; // storage location 0x46ce4d9fc828e2af4f167362c7c43e310c76adc313cd8fe11e785726f972b4f6 from keccak("org.quark.relayer")
    *   address owner;   // storage location 0x3bb5ebf00f3b539fbe3d28370e5631dd2bb9520dffcea6daf564f94582db8111 from keccak("org.quark.owner")
    *   bool callable;   // storage location 0xabc5a6e5e5382747a356658e4038b20ca3422a2b81ab44fd6e725e9f1e4cf819 from keccak("org.quark.callable")
    *
    * Quark(owner_ address) {
    *   relayer = msg.sender;
    *   owner = owner;
    *   // setCode(Relayer(relayer).readQuark())
    * }
    *
    * function destruct() external {
    *   require(msg.sender == relayer);
    *   selfdestruct(owner);
    * }
    *
    * fallback() external {
    *   require(callable || msg.sender == relayer);
    *    // START YOUR SCRIPT, E.G.
    *    Erc20.approve(Uni, 100);
    *    // END YOUR SCRIPT
    * }
    *
    * Effectively, the Relayer constructs a new contract that
    * loads its inner code by calling back to the Relayer's `readQuark()`
    * function.
    *
    * Next, once the contract is deployed, the Relayer calls the new
    * contract, triggering the fallback and initiating the user code.
    *
    * Finally, the Relayer calls the `destruct` function to self-destruct
    * the contract (so it can be replaced later).
    *
    * Note: the contract code is may, at its discretion, set `callable = true`
    *       in storage. This indicates that the contract is willing to accept
    *       calls from other contracts (not just the relayer). Effectively,
    *       this means the user script needs to read calldata and/or direct
    *       actions based on the caller. This is not complex, but it seems
    *       fair that scripts should decide to opt into this behavior.
  }
}
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
      if gt(v, 0xffffff) {
        // operand too large
        revert(0, 0)
      }

      mstore8(add(op_idx, 1), byte(29, v))
      mstore8(add(op_idx, 2), byte(30, v))
      mstore8(add(op_idx, 3), byte(31, v))
    }

    function copy4(dst, v) {
      if gt(v, 0xffffffff) {
        // operand too large
        revert(0, 0)
      }

      mstore8(add(dst, 0), byte(28, v))
      mstore8(add(dst, 1), byte(29, v))
      mstore8(add(dst, 2), byte(30, v))
      mstore8(add(dst, 3), byte(31, v))
    }

    function revert_err(offset, size) {
      datacopy(0, offset, size)
      revert(0, size)
    }

    // Load the caller from construction parameters
    let account_idx := allocate(32)
    datacopy(account_idx, datasize("Quark"), 32)
    let account := mload(account_idx)

    // Call back to the Relayer contract (who is the caller) to get the Quark code
    let read_quark_abi := allocate(0x04)
    copy4(read_quark_abi, 0xec8927c0) // readQuark()
    let succ := call(gas(), caller(), 0, read_quark_abi, 0x04, 0, 0)

    if iszero(succ) {
      // This is an unexpected failure
      revert_err(dataoffset("trx script reverted"), datasize("trx script reverted"))
    }

    let appendix_size := datasize("Appendix")

    // Read the return data from the Relayer
    let quark_size := sub(returndatasize(), 0x40) // 0x00-20: header, 0x20-40: "size"
    let total_size := add(quark_size, appendix_size)
    let quark_offset := allocate(total_size)
    returndatacopy(quark_offset, 0x40, quark_size)

    // Storage owner and relayer at respective locations
    sstore(0x3bb5ebf00f3b539fbe3d28370e5631dd2bb9520dffcea6daf564f94582db8111, account)  // owner
    sstore(0x46ce4d9fc828e2af4f167362c7c43e310c76adc313cd8fe11e785726f972b4f6, caller()) // relayer

    // TODO: We could make this better, just testing

    // Next, let's make sure the script starts with the magic incantation (0x303030505050)
    switch eq(shr(208, mload(quark_offset)), 0x303030505050) // top 6 of 32 bytes is >> 26 bytes * 8 bits = 208
    case false {
      // revert_err(dataoffset("trx script invalid"), datasize("trx script invalid"))

      // Buyer beware here!
      // Return the Quark data
      return(quark_offset, quark_size)
    }
    case true {
      // This is overwriting the magic number!
      datacopy(quark_offset, dataoffset("Prependix"), datasize("Prependix"))

      let appendix_jump_dst := add(quark_size, 1)

      // Set the JUMP3 value, byte by byte
      rewrite_push_3(quark_offset, appendix_jump_dst)

      let appendix_offset := add(quark_offset, quark_size)

      // Write the appendix
      datacopy(appendix_offset, dataoffset("Appendix"), datasize("Appendix"))

      // Rewrite `ret` in the appendix
      rewrite_push_3(add(appendix_offset, 0x002), 0x5)
      // Rewrite `offset` in the appendix
      rewrite_push_3(add(appendix_offset, 0x006), quark_size)

      // Return the Quark data
      return(quark_offset, total_size)
    }
  }

  /*
   * 000: PUSH3 XXX // Appendix index
   * 004: JUMP
   * 005: JUMPDEST
   */
  data "Prependix" hex"62000000565B"

  /**
    * Pseudocode
    *
    * code {
    *   function selector() -> s {
    *     s := div(calldataload(0), 0x100000000000000000000000000000000000000000000000000000000)
    *   }
    *
    *   switch selector()
    *     case 0x2b68b9c6 { // "destruct()"
    *       // require(msg.sender == relayer)
    *       if (iszero(eq(caller, sload(0x46ce4d9fc828e2af4f167362c7c43e310c76adc313cd8fe11e785726f972b4f6)))) {
    *         revert(0, 0)
    *       }
    *       // selfdestruct(owner)
    *       selfdestruct(sload(0x3bb5ebf00f3b539fbe3d28370e5631dd2bb9520dffcea6daf564f94582db8111));
    *     }
    *
    *     // require(callable || msg.sender == relayer);
    *     let callable := and(sload(0xabc5a6e5e5382747a356658e4038b20ca3422a2b81ab44fd6e725e9f1e4cf819), 1);
    *     let from_relayer := eq(caller, sload(0x46ce4d9fc828e2af4f167362c7c43e310c76adc313cd8fe11e785726f972b4f6))
    *     if (and(iszero(callable), iszero(from_relayer))) {
    *       revert(0, 0);
    *     }
    *
    *     // JUMP TO USER CODE
    *   }
    * }
    *
    * Pseudocode [Limited jumps]
    *
    * code {
    *   is_destruct := eq(0x2b68b9c6, div(calldataload(0), 0x100000000000000000000000000000000000000000000000000000000))
    *   is_relayer := eq(caller, sload(0x46ce4d9fc828e2af4f167362c7c43e310c76adc313cd8fe11e785726f972b4f6))
    *   is_callable := eq(sload(0xabc5a6e5e5382747a356658e4038b20ca3422a2b81ab44fd6e725e9f1e4cf819), 0x1);
    *   if and(eq(is_destruct, 0), or(is_relayer, is_callable)
    *     // JUMP TO USER CODE
    *   if (and(is_destruct, is_relayer))
    *     selfdestruct(owner)
    *   revert(0, 0)
    * }
    *
    * Opcodes
    *
    * QUARKSTART
    * 000: fe          INVALID
    * 001: 5b          JUMPDEST
    * 002: 62000000    PUSH3 xxxxxx                            [ret]
    * 006: 62000000    PUSH3 xxxxxx                            [ret, code_offset]
    * 00a: 7c0100000000000000000000000000000000000000000000000000000000 PUSH29 `function is_destruct()`
    * 028: 6000        PUSH1 00      
    * 02a: 35          CALLDATALOAD
    * 02b: 04          DIV
    * 02c: 632b68b9c6  PUSH4 0x2b68b9c6
    * 031: 14          EQ                                      [ret, code_offset, is_destruct]
    * 032: 7f46ce4d9fc828e2af4f167362c7c43e310c76adc313cd8fe11e785726f972b4f6 PUSH32 `function is_relayer()`
    * 053: 54          SLOAD
    * 054: 33          CALLER
    * 055: 14          EQ                                      [ret, code_offset, is_destruct, is_relayer]
    * 056: 7fabc5a6e5e5382747a356658e4038b20ca3422a2b81ab44fd6e725e9f1e4cf819 PUSH32 `function is_callable()`
    * 077: 54          SLOAD
    * 078: 6001        PUSH1 0x1
    * 07a: 14          EQ                                      [ret, code_offset, is_destruct, is_relayer, is_callable]
    * 07b: 82          DUP3                                    [ret, code_offset, is_destruct, is_relayer, is_callable, is_destruct]
    * 07c: 6000        PUSH1 0
    * 07e: 14          EQ                                      [ret, code_offset, is_destruct, is_relayer, is_callable, !is_destruct]
    * 07f: 82          DUP3                                    [ret, code_offset, is_destruct, is_relayer, is_callable, !is_destruct, is_relayer]
    * 080: 82          DUP3                                    [ret, code_offset, is_destruct, is_relayer, is_callable, !is_destruct, is_relayer, is_callable]
    * 081: 17          OR                                      [ret, code_offset, is_destruct, is_relayer, is_callable, !is_destruct, is_relayer || is_callable]
    * 082: 16          AND                                     [ret, code_offset, is_destruct, is_relayer, is_callable, !is_destruct && ( is_relayer || is_callable )]
    * 083: 84          DUP5                                    [ret, code_offset, is_destruct, is_relayer, is_callable, !is_destruct && ( is_relayer || is_callable ), code_offset]
    * 084: 62000099    PUSH3 // pc destruct location           [ret, code_offset, is_destruct, is_relayer, is_callable, !is_destruct && ( is_relayer || is_callable ), code_offset, rel_jump]
    * 088: 01          ADD                                     [ret, code_offset, is_destruct, is_relayer, is_callable, !is_destruct && ( is_relayer || is_callable ), code_offset + rel_jump]
    * 089: 57          JUMPI // user code jump location        [ret, code_offset, is_destruct, is_relayer, is_callable]
    * 08a: 81          DUP2                                    [ret, code_offset, is_destruct, is_relayer, is_callable, is_relayer]
    * 08b: 83          DUP4                                    [ret, code_offset, is_destruct, is_relayer, is_callable, is_relayer, is_destruct]
    * 08c: 16          AND                                     [ret, code_offset, is_destruct, is_relayer, is_callable, is_relayer && is_destruct]
    * 08d: 84          DUP5                                    [ret, code_offset, is_destruct, is_relayer, is_callable, is_relayer && is_destruct, code_offset]
    * 08e: 6200009f    PUSH3 // pc destruct location           [ret, code_offset, is_destruct, is_relayer, is_callable, is_relayer && is_destruct, code_offset, rel_jump]
    * 092: 01          ADD                                     [ret, code_offset, is_destruct, is_relayer, is_callable, is_relayer && is_destruct, code_offset + rel_jump]
    * 093: 57          JUMPI
    * 094: 6000        PUSH1 0
    * 096: 6000        PUSH1 0
    * 098: fd          REVERT
    * 099: 5b          JUMPDEST // user code jump location     [ret, code_offset, is_destruct, is_relayer, is_callable]
    * 09a: 50          POP                                     [ret, code_offset, is_destruct, is_relayer]
    * 09b: 50          POP                                     [ret, code_offset, is_destruct]
    * 09c: 50          POP                                     [ret, code_offset]
    * 09d: 50          POP                                     [ret]
    * 09e: 56          JUMP
    * 09f: 5b          JUMPDEST // destruct location
    * 0a0: 7f3bb5ebf00f3b539fbe3d28370e5631dd2bb9520dffcea6daf564f94582db8111 PUSH32
    * 0c1: 54          SLOAD
    * 0c2: ff          SELFDESTRUCT
    * QUARKEND
    */

  data "Appendix" hex"fe5b62000000620000007c010000000000000000000000000000000000000000000000000000000060003504632b68b9c6147f46ce4d9fc828e2af4f167362c7c43e310c76adc313cd8fe11e785726f972b4f65433147fabc5a6e5e5382747a356658e4038b20ca3422a2b81ab44fd6e725e9f1e4cf81954600114826000148282171684620000990157818316846200009f015760006000fd5b50505050565b7f3bb5ebf00f3b539fbe3d28370e5631dd2bb9520dffcea6daf564f94582db811154ff"

  // Errors
  data "trx script reverted" hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000137472782073637269707420726576657274656400000000000000000000000000"
  data "trx script invalid" hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000127472782073637269707420696e76616c69640000000000000000000000000000"
}
