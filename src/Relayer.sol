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
    return hex"5f6101118180a180806004610012610090565b60ec8153608960018201536027600282015360c0600382015382335af11561008d5760173d81810192610086610047856100ca565b938383863e600560126100586100ad565b6020610122823951956006610105893961007560018201896100e6565b8088019361010b85390191016100e6565b5533600155f35b80fd5b6040519081156100a4575b60048201604052565b6060915061009b565b6040519081156100c1575b60208201604052565b606091506100b8565b906040519182156100dd575b8201604052565b606092506100d6565b9060ff60039180601d1a600185015380601e1a60028501531691015356fe62000000565bfe5b600254620000005760016002556005565b600054ff";
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
    console.log(quarkSize);
    uint256 quarkSize_ = quarkSize;
    bytes memory quark = new bytes(quarkSize_);
    uint256 chunks = wordSize(quarkSize_);
    for (uint256 i = 0; i < chunks; i++) {
      bytes32 chunk = quarkChunks[i];
      assembly {
        // TODO: Is there an easy way to do this in Solidity?
        // Note: the last one can overrun the size, but I think that's okay
        mstore(add(quark, add(32, mul(i, 32))), chunk)
      }
    }
    console.logBytes(quark);
    return quark;
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
      console.logBytes32(chunk);
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
    require(!quarkRunning, "quark already running");
    assembly { log1(0, 0, 0x50) }
    saveQuark(quarkCode);
    quarkRunning = true;

    assembly { log1(0, 0, 0x51) }
    bytes memory initCode = abi.encodePacked(
      getQuarkInitCodeXX(),
      abi.encode(msg.sender)
    );
    uint256 initCodeLen = initCode.length;
    //console.logBytes(initCode);

    assembly { log1(0, 0, initCodeLen) }
    Quark quark;
    Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D).breakpoint("a");
    assembly {
      quark := create2(0, add(initCode, 32), initCodeLen, 0)
    }
    assembly { log1(0, 0, 0x53) }
    assembly { log1(0, 0, quark) }

    quarkRunning = false; // TODO: is this right spot?
    clearQuark();

    assembly { log1(0, 0, 0x54) }

    bool quarkCreated;
    assembly {
      quarkCreated := xor(iszero(extcodesize(quark)), 1)
    }
    assembly { log1(0, 0, quarkCreated) }
    require(quarkCreated, "quark init failed");

    (bool callSuccess, bytes memory res) = address(quark).call{value: msg.value}(hex"");
    require(callSuccess, "quark call failed");

    quark.destruct145();

    return res;
  }
}
