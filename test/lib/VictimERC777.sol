// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "openzeppelin/token/ERC777/ERC777.sol";
import "openzeppelin/token/ERC20/ERC20.sol";
import "openzeppelin/token/ERC777/IERC777Recipient.sol";

contract VictimERC777 is ERC20 {
    constructor() ERC20("Victim", "VCTM") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    // Enable receiving callback by overriding ERC777 implementation for testing on reentrant attacks
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        super.transfer(recipient, amount);
        IERC777Recipient(recipient).tokensReceived(address(0), msg.sender, recipient, amount, "", "");
        return true;
    }
}
