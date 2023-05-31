import { describe, expect, test } from '@jest/globals';
import { Value, Bytes } from '../src/Value';
import { callSig } from '../src/Util';

describe('callSig', () => {
  test('for transfer fn', () => {
    expect(
      callSig('transfer(address,uint256)').get()
    ).toEqual('0xa9059cbb')
  });
});
