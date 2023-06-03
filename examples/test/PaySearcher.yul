object "PaySearcher" {
  code {
    verbatim_0i_0o(hex"303030505050")

    // Pays the searcher 50e18 tokens for submitting
    verbatim_0i_0o(hex"60a96080536005608153609c60825360bb608353326084527f000000000000000000000000000000000000000000000002b5e3af16b188000060a452600060006044608060007f000000000000000000000000F62849F9A0B5Bf2913b396098F7c7019b51A820a5af150")

    /* Pay Searcher [VERBATIM]
     * 
     * TODO: Prevent double pay if in callback mode!!
     *
     * Erc20 at 0xF62849F9A0B5Bf2913b396098F7c7019b51A820a
     * Amount 50e18 = 50000000000000000000
     *
     * if (msg.sender == relayer) {
     *   mstore8(0x80, 0xa9)
     *   mstore8(0x81, 0x05)
     *   mstore8(0x82, 0x9c)
     *   mstore8(0x83, 0xbb)
     *   mstore(0x84, origin())
     *   mstore(0xa4, 50000000000000000000)
     *   pop(call(gas(), 0xF62849F9A0B5Bf2913b396098F7c7019b51A820a, 0, 0x80, 0x44, 0, 0))
     * }
     *
     * Opcodes
     *
     * 33   [CALLER]
     * 7f46ce4d9fc828e2af4f167362c7c43e310c76adc313cd8fe11e785726f972b4f6 [PUSH32] keccak("org.quark.relayer")
     * 54   [SLOAD]
     * 14   [EQ]
     * 6001 [PUSH1 0x01]
     * 18   [XOR]
     * 62000000 [PUSH3]
     * 57   [JUMPI]
     * 60a9 [PUSH1 0xa9]
     * 6080 [PUSH1 0x80]
     * 53   [MSTORE8]
     * 6005 [PUSH1 0x05]
     * 6081 [PUSH1 0x81]
     * 53   [MSTORE8]
     * 609c [PUSH1 0x9c]
     * 6082 [PUSH1 0x82]
     * 53   [MSTORE8]
     * 60bb [PUSH1 0xbb]
     * 6083 [PUSH1 0x83]
     * 53   [MSTORE8]
     * 32   [ORIGIN]
     * 6084 [PUSH1 0x84]
     * 52   [MSTORE]
     * 7f000000000000000000000000000000000000000000000002b5e3af16b1880000 [PUSH32]
     * 60a4 [PUSH1 0xa4]
     * 52   [MSTORE]
     * 6000 [PUSH1 0x00]
     * 6000 [PUSH1 0x00]
     * 6044 [PUSH1 0x44]
     * 6080 [PUSH1 0x80]
     * 6000 [PUSH1 0x00]
     * 7f000000000000000000000000F62849F9A0B5Bf2913b396098F7c7019b51A820a [PUSH32]
     * 5a   GAS
     * f1   CALL
     * 50   POP
     * 5b   JUMPDEST
     */

    let account := sload(0)
    log1(0, 0, account)
    switch account
    case 0x88 {
      log1(0, 0, 0x8888)
    }
    case 0x99 {
      log1(0, 0, 0x9999)
    }

    let counter := 0x2e234DAe75C793f67A35089C9d99245E1C58470b

    // increment()
    let sig := 0xd09de08a

    mstore(0x80, sig)

    pop(call(gas(), counter, 0, 0x9c, 4, 0, 0))
    pop(call(gas(), counter, 0, 0x9c, 4, 0, 0))
    pop(call(gas(), counter, 0, 0x9c, 4, 0, 0))

    return (0, 0)
  }
}
