object "GetOwner" {
  code {
    verbatim_0i_0o(hex"303030505050")

    codecopy(0, sub(codesize(), 0x40), 0x40)
    let relayer := mload(0x00)
    let owner := mload(0x20)

    mstore(0x00, owner)
    log1(0, 0, owner)
    switch owner
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

    return (0, 32)
  }
}
