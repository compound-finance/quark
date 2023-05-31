import { describe, expect, test, beforeEach } from '@jest/globals';
import { Contract } from '@ethersproject/contracts';
import { Address, Uint256, Value } from '../src/Value';
import { Action, pipe, pop, __resetVarIndex } from '../src/Action';
import { pipeline } from '../src/Pipeline';
import { prepare } from '../src/Command';
import { cUSDCv3 } from '../src/builtins/comet/arbitrum';
import * as Uniswap from '../src/builtins/uniswap/arbitrum';
import * as Erc20 from '../src/builtins/tokens';
import * as Quark from '../src/Quark';
import { invoke, readUint256 } from '../src/Quark';

describe('Example commands', () => {
  beforeEach(() => {
    __resetVarIndex();
  });

  test('Comet Supply [Arbitrum]', async () => {
    let action = pipeline([
      Erc20.approve(cUSDCv3.underlying, cUSDCv3.address, Quark.UINT256_MAX),
      cUSDCv3.supply(cUSDCv3.underlying, Erc20.balanceOf(cUSDCv3.underlying, cUSDCv3.address)),
    ]);

    let command = await prepare(action);

    expect(command.yul).toMatch('function cUSDCv3Supply');
    expect(command.bytecode).toMatch(/^0x303030505050/);
    expect(command.description).toEqual(`Pipeline:
  * Erc20 Approve
  * Erc20 Balance of |> Supply to Comet [cUSDCv3][Mainnet]`);
  });

  test('Comet Supply [Arbitrum] via Pipe', async () => {
    let action = Quark.pipeline([
      pipe(Erc20.balanceOf(cUSDCv3.underlying, cUSDCv3.address), (bal) => [
        Erc20.approve(cUSDCv3.underlying, cUSDCv3.address, bal),
        cUSDCv3.supply(cUSDCv3.underlying, bal),
      ])
    ]);

    let command = await prepare(action);

    expect(command.yul).toMatch('function cUSDCv3Supply');
    expect(command.bytecode).toMatch(/^0x303030505050/);
    expect(command.description).toEqual(`Pipeline:
  * Erc20 Balance of |> Pipeline:
  * Erc20 Approve
  * Supply to Comet [cUSDCv3][Mainnet]`);
  });

  test('Uniswap Swap', async () => {
    let action = Quark.pipeline([
        Quark.pipe(Uniswap.singleSwap(cUSDCv3.underlying, Erc20.arbitrum.uni, new Quark.Uint256(1e18)), (swapAmount) => [
          Erc20.approve(Erc20.arbitrum.uni, cUSDCv3.address, swapAmount),
          cUSDCv3.supply(cUSDCv3.underlying, swapAmount),
        ]),
    ]);

    let command = await prepare(action);

    expect(command.yul).toMatch('function cUSDCv3Supply');
    expect(command.bytecode).toMatch(/^0x303030505050/);
    expect(command.description).toEqual(`Pipeline:
  * Uniswap Swap [0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb->0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa] |> Pipeline:
  * Erc20 Approve
  * Supply to Comet [cUSDCv3][Mainnet]`);
  });

  test.only('Invocation Example', async () => {
    let provider = {
      _isProvider: true,
      getNetwork: async () => {
        return {
          chainId: 1,
          ensAddress: '0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e',
          name: 'arbitrum'
        }
      }
    } as any;

    let usdc = new Contract("0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", [
      "function balanceOf(address owner) view returns (uint256)",
      "function decimals() view returns (uint8)",
      "function symbol() view returns (string)",
      "function transfer(address to, uint amount) returns (bool)",
      "function approve(address spender, uint amount) returns (bool)",
    ], provider);

    let comet = new Contract("0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", [
      "function supply(address asset, uint256 amount)"
    ], provider);

    let action = pipeline([
      invoke(await usdc.populateTransaction.approve(cUSDCv3.address.get(), Quark.UINT256_MAX.get())),
      pipe(readUint256(usdc.balanceOf(cUSDCv3.address.get())), (bal) => [ // Read from Ethers call
        cUSDCv3.supply(cUSDCv3.underlying, bal) // Can pipe only to built-ins, not to Ethers calls
      ])
    ]);

    let command = await prepare(action);

    expect(command.yul).toMatch('function cUSDCv3Supply');
    expect(command.bytecode).toMatch(/^0x303030505050/);
    expect(command.description).toEqual(`Pipeline:
  * Uniswap Swap [0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb->0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa] |> Pipeline:
  * Erc20 Approve
  * Supply to Comet [cUSDCv3][Mainnet]`);
  });
});
