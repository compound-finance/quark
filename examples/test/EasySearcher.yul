object "Searcher" {
  code {
    verbatim_0i_0o(hex"303030505050")
    log1(0, 0, selector())

    function allocate(size) -> ptr {
      /** Allocates memory in a safe way. Returns a pointer to it.
        */
        ptr := mload(0x40)
        if iszero(ptr) { ptr := 0x60 }
        mstore(0x40, add(ptr, size))
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

    function selector() -> s {
      s := div(calldataload(0), 0x100000000000000000000000000000000000000000000000000000000)
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

    function balance_of(account, token) -> b {
      let calldat := allocate(0x24)
      let balance_ptr := allocate(0x20)
      copy4(calldat, 0x70a08231) // balanceOf(address)
      mstore(add(calldat, 0x04), account)
      let res := call(gas(), token, 0, calldat, 0x24, balance_ptr, 0x20)
      if iszero(res) {
        revert_err(dataoffset("balance check failed"), datasize("balance check failed"))
      }
      b := mload(balance_ptr)
    }

    function revert_err(offset, size) {
      // revert_err(dataoffset("XXX"), datasize("XXX"))
      datacopy(0, offset, size)
      revert(0, size)
    }

    switch selector()
    case 0x256b1b88 /* "submitSearch(address,bytes,address,address,uint256)" */ {
      let relayer := decode_as_address(0)
      let recipient := decode_as_address(2)
      let pay_token := decode_as_address(3)
      let expected_windfall := decode_as_address(4)
      let relayer_calldata_sz := decode_as_uint(5)
      let relayer_calldata := allocate(relayer_calldata_sz)
      calldatacopy(relayer_calldata, 0xc4, relayer_calldata_sz)

      let balance_pre := balance_of(recipient, pay_token)

      let res := call(gas(), relayer, 0, relayer_calldata, relayer_calldata_sz, 0, 0)
      if iszero(res) {
        revert_err(dataoffset("searcher call failed"), datasize("searcher call failed"))
      }

      let balance_post := balance_of(recipient, pay_token)

      if or(lt(balance_post, balance_pre), lt(sub(balance_post, balance_pre), expected_windfall)) {
        revert_err(dataoffset("insufficient windfall"), datasize("insufficient windfall"))
      }

      return(0, 0)
    }
    default {
      revert(0, 0)
    }
  }

  data "searcher call failed" hex"0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000001473656172636865722063616c6c206661696c6564000000000000000000000000"
  data "insufficient windfall" hex"00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000015696e73756666696369656e742077696e6466616c6c0000000000000000000000"
  data "balance check failed" hex"0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000001462616c616e636520636865636b206661696c6564000000000000000000000000"
}
