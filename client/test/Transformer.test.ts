import { describe, expect, test, beforeEach } from '@jest/globals';
import { transform } from '../src/Transformer';

/**
 * 00: 6003 [PUSH1]
 * 02: 56   [JMP]
 * 03: 5b   [JMPDEST]
 * 04: 5F   [PUSH0]
 * 05: 50   [POP]
 * 06: 5b   [JMPDEST]
 * 07: 6006 [PUSH0]
 * 09: 56   [JUMP]
 * 0a: 5b   [JUMPDEST]
 * 
 * 
 * 
 *
 *
 *
 * 00: 6003   [PUSH1]
 * 02: 5f565b [PUSH0+JMP+JUMPDEST]
 * 04: 56     [JMP]
 * 05: 5b     [JMPDEST]
 * 06: 5F     [PUSH0]
 * 07: 50     [POP]
 * 08: 5b     [JMPDEST]
 * 09: 6006   [PUSH0]
 * 0b: 5f565b [PUSH0+JMP+JUMPDEST]
 * 0d: 56     [JUMP]
 * 0e: 5b     [JUMPDEST]
 */
describe('Transformer', () => {
  test('Transforms script with no jumps', () => {
    expect(transform('0x600050')).toEqual(`0x303030505050600050`);
  });

  test('Transforms script with simple jump', () => {
    expect(transform('0x6003565b')).toEqual(`0x3030305050506003600301565b`);
  });

  // test('Transforms script with simple jump increasing op size', () => {
  //   expect(transform('0x60ff565b')).toEqual(`0x3030305050506008565b`);
  // });

  // TODO: Same test but with future instructions landing at correct new destinations

  test('Transforms script with multiple jumps', () => {
    expect(transform('0x6000506006565b5b6100025061000757fe')).toEqual(`0x6000506006600601565b5b6100025061000760060157fe`);
  });

  // test('Fails on dynamic jump', () => {
  //   expect(transform('0x6005600101565b')).toEqual(`err`);
  // });

  // test('Counter form', () => {
  //   expect(transform('0x608060405234801561001057600080fd5b506004361061002b5760003560e01c8063522bb70414610030575b600080fd5b61004361003e366004610194565b610045565b005b806001600160a01b031663d09de08a6040518163ffffffff1660e01b8152600401600060405180830381600087803b15801561008057600080fd5b505af1158015610094573d6000803e3d6000fd5b50505050806001600160a01b031663d09de08a6040518163ffffffff1660e01b8152600401600060405180830381600087803b1580156100d357600080fd5b505af11580156100e7573d6000803e3d6000fd5b50505050806001600160a01b031663d09de08a6040518163ffffffff1660e01b8152600401600060405180830381600087803b15801561012657600080fd5b505af115801561013a573d6000803e3d6000fd5b50505050806001600160a01b031663d09de08a6040518163ffffffff1660e01b8152600401600060405180830381600087803b15801561017957600080fd5b505af115801561018d573d6000803e3d6000fd5b5050505050565b6000602082840312156101a657600080fd5b81356001600160a01b03811681146101bd57600080fd5b939250505056fea2646970667358221220ea80a76dc89bab904002528e2a2fbf81f69faf012541d7f2e7c8f7b7b962c65a64736f6c63430008140033')).toEqual(`zzz`);
  // })
});
