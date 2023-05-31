import { Output, compile } from 'solc';
import type { Action } from './Action';
import { UnsignedTransaction } from '@ethersproject/transactions';
import { buildYul } from './Compiler';

export interface Command {
  yul: string,
  description: string,
  bytecode: string
}

function indent(n: number): (s: string) => string {
  let indention = [...new Array(n)].map((_) => ' ').join('');

  return function(s: string): string {
    return s.split('\n').map((x) => indention + x).join('\n');
  }
}

export async function prepare(action: Action<undefined>): Promise<Command> {
  let yul = `
object "QuarkCommand" {
  code {
    verbatim_0i_0o(hex"303030505050")

    function allocate(size) -> ptr {
      ptr := mload(0x40)
      if iszero(ptr) { ptr := 0x60 }
      mstore(0x40, add(ptr, size))
    }

${action.preamble.map(indent(4)).join('\n\n')}

${action.statements.map(indent(4)).join('\n\n')}
  }
}`;

  return buildYul(yul);
}
