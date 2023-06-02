// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Vm.sol";
import "forge-std/console.sol";

interface Quark {
  function destruct145() external;
  fallback() external;
}

contract Relayer {
  bool public quarkRunning;
  uint256 public quarkSize;
  mapping(uint256 => bytes32) quarkChunks;

  function getQuarkAddressXX(address account) external view returns (address) {
    return address(uint160(uint(
      keccak256(
        abi.encodePacked(
          bytes1(0xff),
          address(this),
          uint256(0),
          keccak256(
            abi.encodePacked(
              getQuarkInitCodeXX(),
              abi.encode(account)
            )
          )
        )
      )))
    );
  }

  function getQuarkInitCodeXX() public pure returns (bytes memory) {
    return hex"5f80600461000b6100f1565b61001481610188565b82335af1156100e7573d6083810190603f199060c38282016100358561012b565b93816040863e65303030505050855160d01c036100dd576100969261005861010e565b60206103348239519460066101ab8839610076603e1982018861015c565b8601916101b19083013961008d603d198201610147565b6039190161015c565b7f3bb5ebf00f3b539fbe3d28370e5631dd2bb9520dffcea6daf564f94582db811155337f46ce4d9fc828e2af4f167362c7c43e310c76adc313cd8fe11e785726f972b4f655f35b60606102746101a3565b60606102d46101a3565b604051908115610105575b60048201604052565b606091506100fc565b604051908115610122575b60208201604052565b60609150610119565b9060405191821561013e575b8201604052565b60609250610137565b60036005915f60018201535f60028201530153565b9062ffffff81116101845760ff81600392601d1a600185015380601e1a600285015316910153565b5f80fd5b600360c09160ec815360896001820153602760028201530153565b81905f395ffdfe62000000565bfe5b62000000620000007c01000000000000000000000000000000000000000000000000000000006000350463fed416e5147f46ce4d9fc828e2af4f167362c7c43e310c76adc313cd8fe11e785726f972b4f65433147fabc5a6e5e5382747a356658e4038b20ca3422a2b81ab44fd6e725e9f1e4cf81954600114826000148282171684620000990157818316846200009f015760006000fd5b50505050565b7f3bb5ebf00f3b539fbe3d28370e5631dd2bb9520dffcea6daf564f94582db811154ff000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000127472782073637269707420696e76616c69640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000137472782073637269707420726576657274656400000000000000000000000000";
  }

  function wordSize(uint256 x) internal pure returns (uint256) {
    uint256 r = x / 32;
    if (r * 32 < x) {
      return r + 1;
    } else {
      return r;
    }
  }

  function readQuark() external view returns (bytes memory) {
    require(quarkRunning, "quark not running");
    uint256 quarkSize_ = quarkSize;
    bytes memory quark = new bytes(quarkSize_);
    uint256 chunks = wordSize(quarkSize_);
    for (uint256 i = 0; i < chunks; i++) {
      bytes32 chunk = quarkChunks[i];
      assembly {
        // TODO: Is there an easy way to do this in Solidity?
        // Note: the last one can overrun the size, should we prevent that?
        mstore(add(quark, add(32, mul(i, 32))), chunk)
      }
    }
    return quark;
  }

  function runQuark(bytes memory quarkCode) public payable returns (bytes memory) {
    require(!quarkRunning, "quark already running");
    saveQuark(quarkCode);
    quarkRunning = true;

    bytes memory initCode = abi.encodePacked(
      getQuarkInitCodeXX(),
      abi.encode(msg.sender)
    );
    uint256 initCodeLen = initCode.length;

    Quark quark;
    assembly {
      quark := create2(0, add(initCode, 32), initCodeLen, 0)
    }
    require(uint160(address(quark)) > 0, "quark init failed");

    quarkRunning = false; // TODO: is this right spot to put this?
    clearQuark();

    // TODO: Do we need this double check there's code here?
    uint256 quarkCodeLen;
    assembly {
      quarkCodeLen := extcodesize(quark)
    }
    require(quarkCodeLen > 0, "quark init failed");

    (bool callSuccess, bytes memory res) = address(quark).call{value: msg.value}(hex"");
    require(callSuccess, "quark call failed");

    quark.destruct145();

    // TODO: We should triple check that ran correctly, since we *need* it to.

    return res;
  }

  function saveQuark(bytes memory quark) internal {
    uint256 quarkSize_ = quark.length;
    uint256 chunks = wordSize(quarkSize_);
    for (uint256 i = 0; i < chunks; i++) {
      bytes32 chunk;
      assembly {
        // TODO: Is there an easy way to do this in Solidity?
        chunk := mload(add(quark, add(32, mul(i, 32))))
      }
      quarkChunks[i] = chunk;
    }
    quarkSize = quarkSize_;
  }

  function clearQuark() internal {
    uint256 chunks = wordSize(quarkSize);
    for (uint256 i = 0; i < chunks; i++) {
      quarkChunks[i] = 0;
    }
    quarkSize = 0;
  }

  fallback(bytes calldata quarkCode) external payable returns (bytes memory) {
    return runQuark(quarkCode);
  }
}
