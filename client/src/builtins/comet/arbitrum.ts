import { Value, Bool, Address, Uint256 } from '../../Value';
import { Action, Input, buildAction } from '../../Action';
import { yul } from '../../Yul';
import { callSig } from '../../Util';

let cUSDCv3Address = new Address("0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
let cUSDCv3Underlying = new Address("0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");

export function cUSDCv3Supply(asset: Input<Address>, amount: Input<Uint256>): Action<undefined> {
  return buildAction<[Address, Uint256], undefined>(
    [asset, amount],
    ([asset, amount]) => ({
      preamble: [
        yul`
          function cUSDCv3Supply(asset, amount) {
            let data := allocate(0x44)
            let sig := ${callSig('supply(address,uint256)')}
            mstore(data, sig)
            mstore(add(data, 0x04), asset)
            mstore(add(data, 0x24), amount)
            pop(call(gas(), ${cUSDCv3Address}, 0, data, 0x44, 0, 0))
          }
        `],
      statements: [
        `cUSDCv3Supply(${asset.get()}, ${amount.get()})`
      ],
      description: `Supply to Comet [cUSDCv3][Mainnet]`,
    })
  );
}

export const cUSDCv3 = {
  supply: cUSDCv3Supply,
  address: cUSDCv3Address,
  underlying: cUSDCv3Underlying
};
