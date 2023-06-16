const fs = require('fs');

let [_n, _f, file] = process.argv;

let parsed = JSON.parse(fs.readFileSync(file, 'utf-8'));

let structLogs = parsed.result.structLogs;

let opCounts = {};
let gasCosts = {};

for (let log of structLogs) {
  let simpleOp = log.op.replace(/\d+$/, '');
  opCounts[simpleOp] = ( opCounts[simpleOp] ?? 0 ) + 1;
  gasCosts[simpleOp] = ( gasCosts[simpleOp] ?? 0 ) + log.gasCost;
}

function showOps(o) {
  let entries = Object.entries(o);
  entries.sort((a, b) => a[1] - b[1]);
  for (let [op, val] of entries.reverse()) {
    console.log(`${op}: ${val}`);
  }
}

console.log("Operations:");
console.log(showOps(opCounts));
console.log("");
console.log("Gas Costs:");
console.log(showOps(gasCosts));
console.log("");
console.log("Average Gas Cost:");
console.log(showOps(Object.fromEntries(Object.entries(gasCosts).map(([op, cost]) => [op, cost / opCounts[op]]))));
