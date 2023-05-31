import { describe, expect, test, beforeEach } from '@jest/globals';
import { getRelayer, Relayer } from '../src/Relayer';

describe('Relayer', () => {
  test('getRelayer', async () => {
    let provider = {
      _isProvider: true,
      getNetwork: async () => {
        return {
          chainId: 1,
          ensAddress: '0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e',
          name: 'arbitrum'
        }
      }
    } as any;

    let relayer = await getRelayer(provider);

    expect(relayer.address).toEqual('0xC9c445CAAC98B23D1b7439cD75938e753307b2e6');
    expect(relayer.quarkAddress25).not.toBeUndefined();
  });

  test('Relayer', async () => {
    let provider = {
      _isProvider: true,
      getNetwork: async () => {
        return {
          chainId: 1,
          ensAddress: '0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e',
          name: 'arbitrum'
        }
      }
    } as any;

    let relayer = Relayer(provider, 'arbitrum', 1);

    expect(relayer.address).toEqual('0xC9c445CAAC98B23D1b7439cD75938e753307b2e6');
    expect(relayer.quarkAddress25).not.toBeUndefined();
  });
});
