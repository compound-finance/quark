object "Incrementer" {
  code {
    let counter := 0x2e234DAe75C793f67A35089C9d99245E1C58470b

    // increment()
    let sig := 0xd09de08a

    mstore(0x80, sig)

    pop(call(gas(), counter, 0, 0x9c, 4, 0, 0))
    selfdestruct(counter)
  }
}
