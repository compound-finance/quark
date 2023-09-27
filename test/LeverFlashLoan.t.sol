// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/CodeJar.sol";
import "../src/QuarkWallet.sol";

import "./lib/YulHelper.sol";
import "./lib/LeverFlashLoan.sol";

contract LeverFlashLoanTest is Test {
    CodeJar public codeJar;

    function setUp() public {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        codeJar.saveCode(
            new YulHelper().getDeployed(
                "LeverFlashLoan.sol/LeverFlashLoan.json"
            )
        );
    }

    function testLeverFlashLoan() public {
        address account = address(0xaa);
        QuarkWallet wallet = new QuarkWallet{salt: 0}(account, codeJar);

        bytes memory result = wallet.executeQuarkOperation(
            new YulHelper().getDeployed(
                "LeverFlashLoan.sol/LeverFlashLoan.json"
            ),
            abi.encodeWithSelector(
                LeverFlashLoan.run.selector,
                Comet(0xc3d688B66703497DAA19211EEdff47f25384cdc3),
                0,
                1 ether
            )
        );
    }
}
