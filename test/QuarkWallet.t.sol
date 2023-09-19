// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/CodeJar.sol";
import "../src/QuarkWallet.sol";

import "./lib/Counter.sol";
import "./lib/YulHelper.sol";
import "./lib/Reverts.sol";

contract QuarkWalletTest is Test {
    event Ping(uint256);

    CodeJar public codeJar;
    Counter public counter;

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));
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

    function testQuarkOperationRevertsIfCodeNotFound() public {
        address account = address(0xaa);
        bytes memory code = abi.encode();

        QuarkWallet wallet = new QuarkWallet{salt: 0}(account, codeJar);
        QuarkWallet.QuarkOperation memory operation = QuarkWallet.QuarkOperation({
            code: code,
            encodedCalldata: abi.encodeWithSignature("x()")
        });

        vm.expectRevert(abi.encodeWithSelector(
            QuarkWallet.QuarkCodeNotFound.selector
        ));
        bytes memory result = wallet.executeQuarkOperation(operation);
        console.logBytes(result);
    }

    function testQuarkOperationRevertsIfCallReverts() public {
        address account = address(0xb0b);
        bytes memory revertsCode = new YulHelper().getDeployed("Reverts.sol/Reverts.json");
        QuarkWallet wallet = new QuarkWallet{salt: 0}(account, codeJar);
        vm.expectRevert(abi.encodeWithSelector(
            QuarkWallet.QuarkCallError.selector,
            abi.encodeWithSelector(Reverts.Whoops.selector)
        ));
        wallet.executeQuarkOperation(QuarkWallet.QuarkOperation({
            code: revertsCode,
            encodedCalldata: abi.encode()
        }));
    }

    function testAtomicPing() public {
        bytes memory ping = new YulHelper().getDeployed("Logger.sol/Logger.json");
        // TODO: Check who emitted.
        address account = address(0xb0b);
        QuarkWallet wallet = new QuarkWallet{salt: 0}(account, codeJar);
        vm.expectEmit(false, false, false, true);
        emit Ping(55);
        wallet.executeQuarkOperation(
          QuarkWallet.QuarkOperation({
            code: ping,
            encodedCalldata: abi.encode()
          })
        );
    }

    function testAtomicIncrementer() public {
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");

        assertEq(counter.number(), 0);
        address account = address(0xb0b);
        QuarkWallet wallet = new QuarkWallet{salt: 0}(account, codeJar);
        wallet.executeQuarkOperation(
          QuarkWallet.QuarkOperation({
            code: incrementer,
            encodedCalldata: abi.encodeWithSignature("incrementCounter(address)", counter)
          })
        );
        assertEq(counter.number(), 3);
    }
}
