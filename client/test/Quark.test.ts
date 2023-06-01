import { describe, expect, test, beforeEach } from '@jest/globals';
import { quarkAddress } from '../src/Quark';

describe('Quark functions', () => {
  test('Gets correct quark address', async () => {
    expect(quarkAddress('0xE4a892476d366A1AE55bf53463a367892E885cEE', 'arbitrum')).toEqual(`0xe067c894f828fe5d212a88b4ce7f51b9106882ae`);
  });
});
