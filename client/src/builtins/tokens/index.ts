import { Value, Bool, Address, Uint256 } from '../../Value';
import { Action, buildAction } from '../../Action';
import { yul } from '../../Yul';
import { callSig } from '../../Util';
export * as arbitrum from './arbitrum';

export function approve(asset: Value<Address>, spender: Value<Address>, amount: Value<Uint256>): Action<undefined> {
  return buildAction<[Address, Address, Uint256], undefined>(
    [asset, spender, amount],
    ([asset, spender, amount]) => ({
      preamble: [
        yul`
          function approve(asset, spender, amount) {
            let data := allocate(0x44)
            let sig := ${callSig('approve(address,uint256)')}
            mstore(data, sig)
            mstore(add(data, 0x04), spender)
            mstore(add(data, 0x24), amount)
            pop(call(gas(), asset, 0, data, 0x44, 0, 0))
          }
        `],
      statements: [
        `approve(${asset.get()}, ${spender.get()}, ${amount.get()})`
      ],
      description: `Erc20 Approve`,
    })
  );
}

export function balanceOf(asset: Value<Address>, account: Value<Address>): Action<Uint256> {
  return buildAction<[Address, Address], Uint256>(
    [asset, account],
    ([asset, account]) => ({
      preamble: [
        yul`
          function balanceOf(asset, account) -> b {
            let data := allocate(0x24)
            let res := allocate(0x20)
            let sig := ${callSig('balanceOf(address)')}
            mstore(data, sig)
            mstore(add(data, 0x04), account)
            pop(call(gas(), asset, 0, data, 0x24, res, 0x20))
            b := mload(res)
          }
        `],
      statements: [
        `balanceOf(${asset.get()}, ${account.get()})`
      ],
      description: `Erc20 Balance of`,
    })
  );
}
