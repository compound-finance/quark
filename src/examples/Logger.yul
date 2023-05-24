object "Logger" {
  code {
    mstore(0x80, 55)
    // Ping(uint256)
    let topic := 0x48257dc961b6f792c2b78a080dacfed693b660960a702de21cee364e20270e2f
    log1(0x80, 0x20, topic)
    return(0, 0)
  }
}
