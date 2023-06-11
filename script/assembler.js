const fs = require('fs');
const opcodes = require('./opcodes');

function encode(instruction, ...data) {
  let cleanOpcode = instruction.trim().toUpperCase();
  if (!(cleanOpcode in opcodes)) {
    throw new Error(`Unknown or invalid opcode: ${instruction}`);
  }

  let [opcode, immediateSize] = opcodes[cleanOpcode];
  
  let result = opcode.toString(16).padStart(2, '0');

  if (immediateSize > 0) {
    if (data.length === 0 || data[0].trim().length === 0) {
      throw new Error(`Missing required data for instruction: ${instruction}`);
    }
    // TODO: Encode to correct number of bytes
    let instructionWidth = immediateSize * 2;
    let extraData = BigInt(data).toString(16).padStart(instructionWidth, '0');
    if (extraData.length > instructionWidth) {
      throw new Error(`Too much data to fit instruction ${instruction}: ${data}`);
    }
    result += extraData;
  }

  return result;
}

let input = process.argv.slice(2).join(' ');
if (input.trim().length === 0) {
  input = fs.readFileSync(process.stdin.fd, 'utf-8');
}

let instructions = input.split(/[\n;]/).map((x) => x.trim()).filter((x) => x.length > 0).map((instruction) => instruction.split(/\s+/));

let code = instructions.map((instructionData) => encode(...instructionData)).join('');

let totalLen = Math.ceil(code.length / 32) * 32;
// encode as abi bytes

let result = '0x' + code.padEnd(totalLen, '0');
process.stdout.write(result);

