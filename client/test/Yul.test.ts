import { describe, expect, test } from '@jest/globals';
import { yul } from '../src/Yul';

describe('Yul template command', () => {
  test('Stripping indention', () => {
    expect(
      yul`
        function _add(x, y) -> r {
          r := add(x, y)
        }
      `
    ).toEqual(`function _add(x, y) -> r {
  r := add(x, y)
}`);
  });
});
