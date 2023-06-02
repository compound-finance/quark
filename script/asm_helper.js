#!env node

const fs = require('fs');
const path = require('path');

let yul = fs.readFileSync(path.join(__dirname, '..', 'src', 'Quark.yul'), 'utf-8');
let scriptRegex = /\*\s*QUARKSTART\s*\n(.*)\n\s*\*\s*QUARKEND/s;
let scriptRes = scriptRegex.exec(yul);
if (!scriptRes) {
  throw new Error(`Cannot find QUARKSTART / QUARKEND in src/Quark.yul`);
}

let [fullText, asm] = scriptRes;

let position = 0;
let bytecode = "";
let finalScript = "* QUARKSTART\n";
for (let line of asm.split('\n')) {
  let checkRegex = /(\s*\*\s*)([\w]{3}):\s*([a-zA-Z0-9]+)(.*)/;
  let res = checkRegex.exec(line);
  if (!res) {
    throw new Error(`Invalid line: ${line}`);
  }
  let [_, header, _pc, operation, rest] = res;
  let positionStr = position.toString(16).padStart(3, '0');
  finalScript += `${header}${positionStr}: ${operation}${rest}\n`;
  position += operation.length / 2;
  bytecode += operation;
}
finalScript += "    * QUARKEND"

let appendixRegex = /data "Appendix" hex"[a-zA-Z0-9]+"/;
if (!yul.includes(fullText) || !yul.match(appendixRegex)) {
  throw new Error("Replacement failure");
}

let finalYul = yul.replace(fullText, finalScript).replace(appendixRegex, `data "Appendix" hex"${bytecode}"`);

fs.writeFileSync(path.join(__dirname, '..', 'src', 'Quark.yul'), finalYul);
