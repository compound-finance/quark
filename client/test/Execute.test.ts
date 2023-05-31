import { describe, expect, test, beforeEach } from '@jest/globals';
import { exec } from '../src/Execute';

describe('Execute', () => {
  test('exec provider', async () => {
    let tx: any;
    let provider = {
      _isSigner: true,
      getChainId: async () => 42161,
      sendTransaction(tx_: any) {
        tx = tx_;
        return 'txres';
      }
    } as any;

    let command = {
      yul: '',
      bytecode: '0xaa',
      description: ''
    };

    expect(await exec(provider, command)).toEqual('txres');
    expect(tx).toEqual({"data": "0xaa", "to": "0xC9c445CAAC98B23D1b7439cD75938e753307b2e6"});
  });
});
