// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../QuarkScript.sol";

interface ITipMulticallErc20 {
  function transfer(address to, uint256 amount) external returns (bool);
}

contract TipMulticall is QuarkScript {
  error InvalidInput();
  error CallError(uint256 n, address wrappedContract, bytes wrappedCalldata, bytes err);

  function run(bytes calldata data) internal override returns (bytes memory) {
    (ITipMulticallErc20 tipToken, uint256 amount, address[] memory wrappedContracts, bytes[] memory wrappedCalldatas) = abi.decode(data, (ITipMulticallErc20, uint256, address[], bytes[]));
    if (wrappedContracts.length != wrappedCalldatas.length) {
      revert InvalidInput();
    }

    for (uint256 i = 0; i < wrappedContracts.length; i++) {
      address wrappedContract = wrappedContracts[i];
      bytes memory wrappedCalldata = wrappedCalldatas[i];
      (bool success, bytes memory returnData) = wrappedContract.call(wrappedCalldata);
      if (!success) {
        revert CallError(i, wrappedContract, wrappedCalldata, returnData);
      }
    }

    tipToken.transfer(tx.origin, amount);

    return abi.encode(hex"");
  }
}
