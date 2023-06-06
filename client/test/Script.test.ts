import { describe, expect, test, beforeEach } from '@jest/globals';
import { Contract } from '@ethersproject/contracts';
import { StaticJsonRpcProvider } from '@ethersproject/providers';
import { Provider } from '@ethersproject/abstract-provider';
import { call } from '../src/Script';

let from = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
let to = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

let usdc = new Contract("0x112233445566778899aabbccddeeff0011223344", [
  "function balanceOf(address owner) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
  "function transfer(address to, uint amount) returns (bool)",
], new StaticJsonRpcProvider(''));

describe('Script', () => {
  let tx: any;
  let provider: Provider;

  beforeEach(() => {
    tx = undefined;
    provider = {
      _isSigner: true,
      getChainId: async () => 42161,
      getAddress: () => from,
      sendTransaction(tx_: any) {
        tx = tx_;
        let x = { tx: tx_ } as any;
        x.wait = () => {
          return tx_;
        }
        return x;
      }
    } as any;
  });

  test('single call', async () => {
    await call(provider, usdc, 'transfer', [from, 100e6]);
    expect(tx.data).toMatch(/^0xa3bebbf/);
    expect(tx.to).toEqual('0x66ca95f4ed181c126acbD5aaD21767b20D6ad7da');
  });

  test('single call via populate', async () => {
    await call(provider, usdc.populateTransaction.transfer(from, 100e6));
    expect(tx.data).toMatch(/^0xa3bebbf/);
    expect(tx.to).toEqual('0x66ca95f4ed181c126acbD5aaD21767b20D6ad7da');
  });

  test('multicall', async () => {
    await call(provider, [
      [usdc, 'transfer', [from, 100e6]],
      usdc.populateTransaction.transfer(from, 100e6)
    ]);
    expect(tx.data).toMatch(/^0xa3bebbf/);
    expect(tx.to).toEqual('0x66ca95f4ed181c126acbD5aaD21767b20D6ad7da');
  });
});
