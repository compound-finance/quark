import { Contract } from '@ethersproject/contracts';
import { UnsignedTransaction } from '@ethersproject/transactions';
import { BigNumber } from '@ethersproject/bignumber';
import { hexlify, hexDataLength, hexDataSlice, hexConcat, hexZeroPad } from '@ethersproject/bytes';
import { Action, buildAction } from './Action';
import { Uint256, Address } from './Value';
import { yul } from './Yul';
import { Command, prepare } from './Command';
import { Compile } from './Compiler';

let invocations = 0;

function rightPad(str: string, len: number, padding=' '): string {
  let padLen = Math.max(0, len - str.length);
  return str + [...new Array(padLen)].map(() => padding).join('');
}

export async function wrap(tx: Promise<UnsignedTransaction> | UnsignedTransaction, compile: Compile): Promise<Command> {
  return await prepare(invoke(await tx), compile);
}

export function invoke(tx: UnsignedTransaction): Action<undefined> {
  return invokeInternal(tx, 0);
}

export function readUint256(tx: UnsignedTransaction): Action<Uint256> {
  return invokeInternal(tx, 32);
}

export function readAddress(tx: UnsignedTransaction): Action<Address> {
  return invokeInternal(tx, 32);
}

export function invokeInternal<T>(tx: UnsignedTransaction, returnSz: number): Action<T> {
  let invocationNum = invocations++;
  let functionName = `__invocation__${invocationNum}`;
  let valueHex = BigNumber.from(tx.value ?? 0);
  let data = hexlify(tx.data ?? []);
  let dataSz = hexDataLength(data);

  let chunks = Math.ceil(dataSz / 32);
  let fullSz = chunks * 32;
  let yuls = [...new Array(chunks)].map((_, i) => {
    let start = i * 32;
    let end = Math.min(( i + 1 ) * 32, dataSz);
    let slice = hexDataSlice(data, start, end);
    let padding = hexZeroPad('0x', 32 - ( end - start ))
    let paddedSlice = hexConcat([slice, padding]);
    return `mstore(add(data, ${i * 32}), ${paddedSlice})`
  });

  return buildAction<[], T>(
    [],
    ([]) => ({
      preamble: [
        yul`
          function ${functionName}()${ returnSz > 0 ? ' -> r' : '' } {
            let data := allocate(${fullSz.toString()})
            ${returnSz > 0 ? `let res := allocate(${returnSz.toString()})` : ``}

           ${yuls.join('\n            ')}

           pop(call(gas(), ${tx.to!}, ${valueHex.toHexString()}, data, ${dataSz.toString()}, ${ returnSz > 0 ? 'res' : '0' }, ${ ( returnSz ?? 0 ).toString() }))
            ${ returnSz > 0 ? 'r := mload(res)' : ''}
          }
        `],
      statements: [
        `${functionName}()`
      ],
      description: `Invocation of Ethers function with signature ${data.slice(0, 4)} to contract ${tx.to!}`,
    })
  );
}
