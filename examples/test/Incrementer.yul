object "Incrementer" {
  code {
    verbatim_0i_0o(hex"303030505050")

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
