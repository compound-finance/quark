object "Callback" {
  code {
    verbatim_0i_0o(hex"303030505050")

    let counter := 0x2e234DAe75C793f67A35089C9d99245E1C58470b

    function decode_as_uint(offset) -> v {
      let pos := add(4, mul(offset, 0x20))
      if lt(calldatasize(), add(pos, 0x20)) {
          revert(0, 0)
      }
      v := calldataload(pos)
    }

    function selector() -> s {
      s := div(calldataload(0), 0x100000000000000000000000000000000000000000000000000000000)
    }

    switch selector()
    case 0x4ccf4b30 /* "counterCallback(uint256)" */ {
      let counter_value := decode_as_uint(0x00)
      log1(0, 0, counter_value)

      // increment(uint256)
      let sig := 0x7cf5dab0
      mstore(0x80, sig)
      mstore(0xa0, mul(counter_value, 10))
      pop(call(gas(), counter, 0, 0x9c, 0x24, 0, 0))
      return (0, 0)
    }
    default {
      sstore(0xabc5a6e5e5382747a356658e4038b20ca3422a2b81ab44fd6e725e9f1e4cf819, 0x1)

      // incrementCallback()
      let sig := 0x69eee7a9
      mstore(0x80, sig)
      pop(call(gas(), counter, 0, 0x9c, 4, 0, 0))
      return (0, 0)
    }
  }
}
