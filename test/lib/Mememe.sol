// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

contract Mememe {
    address public immutable me;

    constructor() {
        me = address(this);
    }

    function hello() public view returns (uint256) {
        require(address(this) != me, "it's me, mario");
        return 55;
    }
}
