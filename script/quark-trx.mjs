import { readFileSync } from 'fs';
import * as path from 'path';
import * as solc from 'solc';

function printError(err) {
  console.error();
  console.error(`\x1b[31mError\x1b[0m: ${err}`);
  console.error();
  printUsage();
}

function printUsage() {
  console.error(`usage: quark-trx {targetFile}.yul`);
  console.error(`usage: quark-trx {targetFile}.sol {functionName} \t**Experimental`);
  console.error();
  console.error();
  process.exit(1);
}

let [_n, _f, target, fnName] = process.argv;

if (!target) {
  printUsage();
}

let isYul;
if (target.endsWith('.sol')) {
  isYul = false;

  if (!fnName) {
    printError('you must specify a function when using [experimental] Solidity');
  }
} else if (target.endsWith('.yul')) {
  isYul = true;
} else {
  printError('Please select a .sol or .yul file');
}

let source;
try {
  source = readFileSync(target, 'utf-8');
} catch (e) {
  printError(e);
}

let ir;

if (!isYul) {
  if (source.includes('import')) {
    printError('For experimental .sol support, currently `import`s are not allowed');
  }

  let input = {
    language: 'Solidity',
    sources: {
      'q.sol': {
        content: source
      }
    },
    settings: {
      outputSelection: {
        'q.sol': {
          '*': ['ir']
        }
      }
    }
  };

  let res = JSON.parse(solc.default.compile(JSON.stringify(input)));

  let [ctxName, v] = Object.entries(res.contracts['q.sol'])[0];
  let irBase = v.ir;

  let regex = new RegExp(`(object "${ctxName}_\\d+_deployed" {.+})\\s*}\\s*`, 's');

  let regexMatch = regex.exec(irBase);

  if (!regexMatch) {
    printError('Cannot currently handle Yul produced from .sol file [cannot find deployed contract]');
  }

  let innerObject = regexMatch[1];

  let fnMatch = innerObject.match(new RegExp(`\"function ${fnName}.*\\n\\s*function (\\w+)`));

  if (!fnMatch) {
    printError(`Cannot currently handle Yul produced from .sol file [cannot find function "${fnName}"]`); 
  }

  let fnFullName = fnMatch[1];

  let replaceRegex = /code {.*?function/s;

  if (!innerObject.match(replaceRegex)) {
    printError(`Cannot currently handle Yul produced from .sol file [cannot find function invocation to replace]`); 
  }

  let lines = [
    '',
    'verbatim_0i_0o(hex"303030505050")',
    `${fnFullName}()`,
    'return(0,0)',
    'function'
  ];

  ir = innerObject.replace(replaceRegex, `code {${lines.join('\n            ')}`);
} else {
  ir = source;

  if (!ir.includes(`verbatim_0i_0o(hex"303030505050")`)) {
    // Let's try to insert verbatim for the user
    let insertVerbatimRegex = /^object\s*"\w+"\s*{\s*code\s*{/sm;
    if (ir.match(insertVerbatimRegex)) {
      let m = insertVerbatimRegex.exec(ir)
      let idx = m[0].length;
      ir = [ir.slice(0, idx), `\n    verbatim_0i_0o(hex"303030505050")`, ir.slice(idx)].join('');
    } else {
      printError('Please include `verbatim_0i_0o(hex"303030505050")` at the start of your Yul object.');
    }
  }
}

if (process.env['VERBOSE']) {
  console.error("Intermediate representation:\n\n");
  console.error(ir);
  console.error("\n\n");
}

let input = {
  language: 'Yul',
  sources: {
    'q.yul': {
      content: ir
    }
  },
  settings: {
    "optimizer": {
      "enabled": true,
      "runs": 1
    },
    outputSelection: {
      'q.yul': {
        '*': ['evm.bytecode.object']
      }
    }
  }
};


let yulCompilationRes = JSON.parse(solc.default.compile(JSON.stringify(input)));
let bytecode = Object.values(yulCompilationRes.contracts['q.yul'])[0].evm.bytecode.object;

if (!bytecode.startsWith('303030505050')) {
  printError(`Invalid bytecode produced, does not start with magic incantation 0x303030505050, got: ${bytecode}`);
}

if (process.stdout.isTTY) {
  console.log(`Trx script: 0x${bytecode}`);
  console.log(``)
  console.log(`\nGoerli cast:\n\tcast send --interactive --rpc-url https://goerli-eth.compound.finance "0x412e71DE37aaEBad89F1441a1d7435F2f8B07270" "0x${bytecode}"`);
  console.log(`\nOptimism Goerli cast:\n\tcast send --interactive --rpc-url https://goerli.optimism.io "0x12D356e5C3b05aFB0d0Dbf0999990A6Ec3694e23" "0x${bytecode}"`);
  console.log(`\nArbitrum Goerli cast:\n\tcast send --interactive --rpc-url https://goerli-rollup.arbitrum.io/rpc "0x12D356e5C3b05aFB0d0Dbf0999990A6Ec3694e23" "0x${bytecode}"`);
} else {
  process.stdout.write(`0x${bytecode}`);
}
