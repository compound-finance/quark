object "GetOwner" {
  code {
    verbatim_0i_0o(hex"303030505050")

    let account := sload(0x3bb5ebf00f3b539fbe3d28370e5631dd2bb9520dffcea6daf564f94582db8111)
    mstore(0x00, account)
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

    return (0, 32)
  }
}
