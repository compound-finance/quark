
object "Simple" {
  code {
    log1(0, 0, 0x77)
    log1(0, 0, gas())
    log1(0, 0, msize())
    log1(0, 0, address())
    log1(0, 0, balance(caller()))
    log1(0, 0, selfbalance())
    log1(0, 0, callvalue())
  }
}
