

let asm = `
* 000: fe          INVALID
    * 001: 5b          JUMPDEST
    * 002: 62000000    PUSH3 xxxxxx                            [ret]
    * 006: 62000000    PUSH3 xxxxxx                            [ret, code_offset]
    * 00a: 6000        PUSH1 00      function is_destruct()
    * 00c: 35          CALLDATALOAD
    * 00d: 7c0100000000000000000000000000000000000000000000000000000000 [PUSH29]
    * 02b: 04          DIV
    * 02c: 63fed416e5  PUSH4 0xfed416e5
    * 031: 14          EQ                                      [ret, code_offset, is_destruct]
    * 032: 7f46ce4d9fc828e2af4f167362c7c43e310c76adc313cd8fe11e785726f972b4f6 PUSH32 function is_relayer()
    * 053: 54          SLOAD
    * 054: 33          CALLER
    * 055: 14          EQ                                      [ret, code_offset, is_destruct, is_relayer]
    * 056: 7fabc5a6e5e5382747a356658e4038b20ca3422a2b81ab44fd6e725e9f1e4cf819 PUSH32 function is_callable()
    * 077: 54          SLOAD
    * 078: 6001        PUSH1 0x1
    * 07a: 14          EQ                                      [ret, code_offset, is_destruct, is_relayer, is_callable]
    * 07b: 82          DUP3                                    [ret, code_offset, is_destruct, is_relayer, is_callable, is_destruct]
    * 07c: 6000        PUSH1 0
    * 07e: 14          EQ                                      [ret, code_offset, is_destruct, is_relayer, is_callable, !is_destruct]
    * 07f: 82          DUP3                                    [ret, code_offset, is_destruct, is_relayer, is_callable, !is_destruct, is_relayer]
    * 080: 82          DUP3                                    [ret, code_offset, is_destruct, is_relayer, is_callable, !is_destruct, is_relayer, is_callable]
    * 081: 17          OR                                      [ret, code_offset, is_destruct, is_relayer, is_callable, !is_destruct, is_relayer || is_callable]
    * 082: 16          AND                                     [ret, code_offset, is_destruct, is_relayer, is_callable, !is_destruct && ( is_relayer || is_callable )]
    * 083: 85          DUP6                                    [ret, code_offset, is_destruct, is_relayer, is_callable, !is_destruct && ( is_relayer || is_callable ), ret]
    * 084: 57          JUMPI                                   [ret, code_offset, is_destruct, is_relayer, is_callable] // TODO: this leaves data on the stack, which we probably shouldn't have
    * 085: 81          DUP2                                    [ret, code_offset, is_destruct, is_relayer, is_callable, is_relayer]
    * 086: 83          DUP4                                    [ret, code_offset, is_destruct, is_relayer, is_callable, is_relayer, is_destruct]
    * 087: 16          AND                                     [ret, code_offset, is_destruct, is_relayer, is_callable, is_relayer && is_destruct]
    * 088: 84          DUP5                                    [ret, code_offset, is_destruct, is_relayer, is_callable, is_relayer && is_destruct, code_offset]
    * 089: 62000094    PUSH3 // pc destruct location
    * 08d: 16          ADD
    * 08e: 57          JUMPI
    * 08f: 6000        PUSH1 0
    * 091: 6000        PUSH1 0
    * 093: fd          REVERT
    * 094: 5b          JUMPDEST // destruct location
    * 095: 7f3bb5ebf00f3b539fbe3d28370e5631dd2bb9520dffcea6daf564f94582db8111 PUSH32
    * 0b6: 54          SLOAD
    * 0b7: ff          SELFDESTRUCT
`

let position = 0;
let bytecode = "";
for (let line of asm.trim().split('\n')) {
  let checkRegex = /(\s*\*\s*)([\w]{3}):\s*([a-zA-Z0-9]+)(.*)/;
  let res = checkRegex.exec(line);
  if (!res) {
    throw new Error(`Invalid line: ${line}`);
  }
  let [_, header, _pc, operation, rest] = res;
  let positionStr = position.toString(16).padStart(3, '0');
  console.log(`${header}${positionStr}: ${operation}${rest}`);
  position += operation.length / 2;
  bytecode += operation;
}

console.log(bytecode);