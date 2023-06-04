import { arrayify, hexlify, hexDataLength, hexDataSlice, hexConcat, hexZeroPad } from '@ethersproject/bytes';

const preamble = [0x30, 0x30, 0x30, 0x50, 0x50, 0x50];
function opcodeArgWidth(opcode: number): number {
  if (isPush(opcode)) {
    return opcode - 0x60 + 1;
  } else {
    return 0;
  }
}

function isPush(opcode: number): boolean {
  return opcode >= 0x60 && opcode <= 0x7f;
}

function isJmp(opcode: number): boolean {
  return opcode === 0x56 || opcode === 0x57;
}

export function transform(script: string): string {
  let bytes = arrayify(script);
  let previousOpcode;
  let res: number[] = [];
  for (let i = 0; i < bytes.length; i++) {
    let opcode = bytes[i];
    let argWidth = opcodeArgWidth(opcode);
    let args: Uint8Array = bytes.slice(i + 1, i + 1 + argWidth);

    // peek at next opcode
    let nextOpcode = bytes[i + 1 + argWidth];
    console.log('opcode', opcode.toString(16), 'args', args, nextOpcode);
    if (nextOpcode !== undefined && isJmp(nextOpcode)) {
      if (isPush(opcode)) {
        // Emit the instruction with the offset
        let pushValue = parseInt(hexlify(args).slice(2), 16) + preamble.length;
        if (pushValue >= Math.pow(2, argWidth * 8)) {
          // TODO: Need to handle expanding offset here!
          throw new Error(`Unable to handle expanding pushes`);
        } else {
          let newValue = arrayify('0x' + pushValue.toString(16).padStart(argWidth * 2, '0'));
          console.log({newValue});
          res.push(opcode);
          res.push(...newValue);
        }
      } else {
        // TODO: Expand the error scope
        throw new Error(`Unable to handle dynamic jump`);
      }
    } else {
      // Emit this instruction as is
      res.push(opcode);
      res.push(...args);
    }

    i += argWidth;
  }
  return hexlify(hexConcat([preamble, res]));
}
