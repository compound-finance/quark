// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

contract WackyBeacon {
    bytes public code;

    function setCode(bytes memory code_) external {
        code = code_;
    }
}

contract WackyCode {
    constructor() {
        assembly {
            selfdestruct(origin())
        }
    }

    function hello() external returns (uint256) {
        return 72;
    }

    function destruct() external {
        assembly {
            selfdestruct(origin())
        }
    }
}

contract WackyFun {
    function cool() external returns (uint256) {
        return 88;
    }
}

contract Wacky {
    error Test(uint256);

    constructor(WackyBeacon beacon) {
        bytes memory code = beacon.code();

        assembly {
            return(add(code, 0x20), mload(code))
        }
    }
}
