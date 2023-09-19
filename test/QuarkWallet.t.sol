// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/CodeJar.sol";
import "../src/QuarkWallet.sol";

import "./lib/YulHelper.sol";

contract QuarkWalletTest is Test {
    CodeJar public codeJar;

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));
    }

    function setUp() public {
        // nothing
    }

    function testExecuteQuarkOperation() public {
        address account = address(0xaa);
        QuarkWallet wallet = new QuarkWallet{salt: 0}(account, codeJar);
        QuarkWallet.QuarkOperation memory operation = QuarkWallet.QuarkOperation({
            code: new YulHelper().getDeployed("GetOwner.sol/GetOwner.json"),
            encodedCalldata: abi.encode()
        });
        bytes memory result = wallet.executeQuarkOperation(operation);
        assertEq(result, abi.encode(0xaa));
    }

    function testQuarkOperationRevertsWithBadCode() public {
        address account = address(0xaa);
        bytes memory code = abi.encode(hex"deadbeef")[:36];
        console.logBytes(code);

        QuarkWallet wallet = new QuarkWallet{salt: 0}(account, codeJar);
        QuarkWallet.QuarkOperation memory operation = QuarkWallet.QuarkOperation({
            code: code,
            encodedCalldata: abi.encodeWithSignature("x()")
        });

        vm.expectRevert(abi.encodeWithSelector(
            QuarkWallet.QuarkCallError.selector
        ));
        bytes memory result = wallet.executeQuarkOperation(operation);
        console.logBytes(result);
    }
}
