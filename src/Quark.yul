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

    // Call back to the Relayer contract (who is the caller) to get the Quark code
    // TODO: Better way to setup this call data?
    log1(0, 0, 0x111)
    let read_quark_abi := allocate(0x04)
    mstore8(add(read_quark_abi, 0x00), 0xec)
    mstore8(add(read_quark_abi, 0x01), 0x89)
    mstore8(add(read_quark_abi, 0x02), 0x27)
    mstore8(add(read_quark_abi, 0x03), 0xc0)
    let succ := call(gas(), caller(), 0, read_quark_abi, 0x04, 0, 0)

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
    datacopy(account_idx, datasize("Quark"), 32)
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
