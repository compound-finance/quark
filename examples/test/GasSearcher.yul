object "Searcher" {
  code {
    verbatim_0i_0o(hex"303030505050")

    let gas_pre := gas()

    /**
     * Searcher quark script to take a TrxScript and submit
     * it to the chain iff the venture would be profitable
     * beyond gas fees. It does this by checking its balance
     * in a pay token (e.g. USDC) and comparing it to the
     * gas cost used by the transaction (plus its own base
     * cost), and ensuring it received more than enough
     * to cover its own costs.
     *
     * Note: this script is susceptible to greifing and expects
     *       anti-greifing to be have off-chain remedies, e.g.
     *       by blacklisting addresses that greif or capping
     *       total gas costs.
     *
     * Note: this search only currently works when the payToken
     *       is USDC and the base token is ETH. We could expand
     *       that requirement later.
     */

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

    function chainlink_price(oracle) -> p {
      let calldat := allocate(0x04)
      let res_ptr := allocate(0x20)
      copy4(calldat, 0x50d25bcd) // latestAnswer()
      let res := call(gas(), oracle, 0, calldat, 0x04, res_ptr, 0x20)
      if iszero(res) {
        revert_err(dataoffset("chainlink price failed"), datasize("chainlink price failed"))
      }
      p := mload(res_ptr)
    }

    function lte(a, b) -> r {
      r := iszero(gt(a, b))
    }

    function revert_err(offset, size) {
      // revert_err(dataoffset("XXX"), datasize("XXX"))
      datacopy(0, offset, size)
      revert(0, size)
    }

    function eth_price_in_cents(amt, oracle) -> p {
      // This is specific to how the USDC market works
      // Also, we're using the USD price, not the USDC price
      // But c'est la vie for now.

      // 1e28 for this specific oracle will return the price in cents
      // 1e28=10000000000000000000000000000
      // I need to check on this math better!
      p := div(mul(amt, chainlink_price(oracle)), 10000000000000000000000000000)
    }

    switch selector()
    case 0x19340020 /* "submitSearch(address relayer, bytes calldata relayerCalldata, address recipient, address payToken, address payTokenOracle, uint256 expectedWindfall, uint256 gasPrice)" */ {
      let relayer := decode_as_address(0)
      let recipient := decode_as_address(2)
      let pay_token := decode_as_address(3)
      let pay_token_oracle := decode_as_address(4)
      let expected_windfall := decode_as_address(5)
      let gas_price := decode_as_address(6)
      let relayer_calldata_sz := decode_as_uint(7)
      let relayer_calldata := allocate(relayer_calldata_sz)
      calldatacopy(relayer_calldata, 0x104, relayer_calldata_sz)

      let balance_pre := balance_of(recipient, pay_token)

      let res := call(gas(), relayer, 0, relayer_calldata, relayer_calldata_sz, 0, 0)
      if iszero(res) {
        revert_err(dataoffset("searcher call failed"), datasize("searcher call failed"))
      }

      let balance_post := balance_of(recipient, pay_token)

      if lte(balance_post, balance_pre) {
        revert_err(dataoffset("no balance gain"), datasize("no balance gain"))
      }

      let gas_used := sub(gas_pre, gas())
      if iszero(gas_price) {
        gas_price := gasprice()
      }
      let eth_used := mul(gas_used, gas_price)
      let eth_cost := eth_price_in_cents(eth_used, pay_token_oracle)
      let balance_gain := sub(balance_post, balance_pre)

      log4(0, 0, gas_used, eth_used, eth_cost, balance_gain)

      if lte(balance_gain, eth_cost) {
        revert_err(dataoffset("no windfall"), datasize("no windfall"))
      }

      let windfall := sub(balance_post, eth_cost)

      log4(0, 0, balance_gain, eth_used, eth_cost, windfall)

      if lt(windfall, expected_windfall) {
        revert_err(dataoffset("insufficient windfall"), datasize("insufficient windfall"))
      }

      // Otherwise, we're good!

      return(0, 0)
    }
    default {
      revert(0, 0)
    }
  }

  data "searcher call failed" hex"01"
  data "insufficient windfall" hex"02"
  data "balance check failed" hex"03"
  data "chainlink price failed" hex"04"
  data "no balance gain" hex"05"
  data "no windfall" hex"06"
}
