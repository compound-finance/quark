// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../QuarkScript.sol";

contract Searcher is QuarkScript {
  error NoBalanceGain(uint256 balancePre, uint256 balancePost);
  error InsufficientWindfall(uint256 gasUsed, uint256 gasPrice, uint256 baseFee, uint256 windfall);

  struct SearcherInput {
    address account;
    uint32 nonce;
    uint32[] reqs;
    bytes trxScript;
    bytes trxCalldata;
    uint256 expiry;
    uint8 v;
    bytes32 r;
    bytes32 s;
    address beneficiary;
    uint256 baseFee;
  }

  function run(bytes calldata data) external onlyRelayer returns (bytes memory) {
    SearcherInput memory input = abi.decode(data, (SearcherInput));

    uint256 balancePre = input.beneficiary.balance;
    uint256 gasLeftPre = gasleft();

    bytes memory returnData = relayer().runTrxScript(
      input.account,
      input.nonce,
      input.reqs,
      input.trxScript,
      input.trxCalldata,
      input.expiry,
      input.v,
      input.r,
      input.s
    );

    uint256 gasUsed = gasLeftPre - gasleft();
    uint256 balancePost = input.beneficiary.balance;

    if (balancePost <= balancePre) {
      revert NoBalanceGain(balancePre, balancePost);
    }

    uint256 windfall = balancePost - balancePre;

    if (windfall <= gasUsed * tx.gasprice + input.baseFee) {
      revert InsufficientWindfall(gasUsed, tx.gasprice, input.baseFee, windfall);
    }

    return returnData;
  }
}
