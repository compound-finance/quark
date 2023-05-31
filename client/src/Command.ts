import { Output, compile } from 'solc';
import type { Action } from './Action';

interface Command {
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

export function prepare(action: Action<undefined>): Command {
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

  console.log("Yul");
  console.log(yul);

  let input = {
    language: 'Yul',
    sources: {
      'q.yul': {
        content: yul
      }
    },
    settings: {
      optimizer: {
        enabled: true,
        runs: 1
      },
      evmVersion: "paris",
      outputSelection: {
        'q.yul': {
          '*': ['evm.bytecode.object']
        }
      }
    }
  };

  let yulCompilationRes = JSON.parse(compile(JSON.stringify(input))) as Output;
  console.log(yulCompilationRes);
  let bytecode = Object.values(yulCompilationRes.contracts['q.yul'])[0].evm.bytecode.object as string;

  if (!bytecode.startsWith('303030505050')) {
    throw new Error(`Invalid bytecode produced, does not start with magic incantation 0x303030505050, got: ${bytecode}`);
  }

  return {
    yul,
    description: action.description,
    bytecode: `0x` + bytecode
  };
}
