import { Value, Bool, Address, Uint256 } from '../../Value';
import { Action } from '../../Action';
import { yul } from '../../Yul';
import { callSig } from '../../Util';

let cometAddress = new Address("0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");

export function cUSDCv3Supply(asset: Value<Address>, amount: Value<Uint256>): Action<Bool> {
  return {
    preamble: [
      yul`
        function cUSDCv3Supply(asset, amount) -> success {
          let data := allocate(0x44)
          let sig := ${callSig('supply(address,uint256)')}
          mstore(data, sig)
          mstore(add(data, 0x04), asset)
          mstore(add(data, 0x24), amount)
          success := call(gas(), ${cometAddress}, 0, data, 0x44, 0, 0)
        }
      `],
    statements: [
      `cUSDCv3Supply(${asset.get()}, ${amount.get()})`
    ],
    description: `Supply to Comet [cUSDCv3][Mainnet]`, // TODO: This is weird and wrong
    _: undefined,
  }
}
