import { readFileSync } from 'fs';
import * as path from 'path';
import * as solc from 'solc';

let [_n, _f, ctxName, fnName] = process.argv;

let ir = readFileSync(path.join(process.cwd(), 'out', `${ctxName}.sol`, `${ctxName}.ir`), 'utf-8');

let regex = new RegExp(`(object "${ctxName}_\\d+_deployed" {.+})\\s*}\\s*`, 's');

let [_str, inner] = regex.exec(ir);

console.log(inner);


let [_ff, fnFullName] = inner.match(new RegExp(`\"function ${fnName}.*\\n\\s*function (\\w+)`))
console.log(fnFullName);
let innerFixed = inner.replace(/code {.*?function/s, `code {\n            verbatim_0i_0o(hex"303030505050")\n            ${fnFullName}()\n\n            function`)
console.log("fixed!!")
console.log(innerFixed);

var input = {
  language: 'Yul',
  sources: {
    'q.yul': {
      content: innerFixed
    }
  },
  settings: {
    outputSelection: {
      'q.yul': {
        '*': ['evm.bytecode.object']
      }
    }
  }
};

let res = JSON.parse(solc.default.compile(JSON.stringify(input)));

console.log(Object.values(res.contracts['q.yul'])[0].evm.bytecode.object);
