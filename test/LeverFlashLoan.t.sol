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

    uint alicePrivateKey =
        0xc91f84c86234ca4d2b175a54df651d113afe37d878bca22fe9499e39035be32b;

    function setUp() public {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        codeJar.saveCode(
            new YulHelper().getDeployed(
                "LeverFlashLoan.sol/LeverFlashLoan.json"
            )
        );

        address alice = vm.addr(1);
        vm.createWallet(uint256(keccak256(bytes("1"))));
        emit log_address(alice);
        // Wallet memory wallet = vm.createWallet(uint256(keccak256(bytes("1"))));
        // vm.createWallet(
        //     "0xc91f84c86234ca4d2b175a54df651d113afe37d878bca22fe9499e39035be32b"
        // );
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
                2,
                1 ether
            )
        );
    }
}
