// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdMath.sol";

import "./../../src/QuarkWallet.sol";
import "./../../src/QuarkWalletFactory.sol";
import "./../../src/terminal_scripts/TerminalScript.sol";
import "./../lib/YulHelper.sol";
import "./../lib/SignatureHelper.sol";
import "./../lib/Counter.sol";

/**
 * Scenario test for uesr borrow base asset from Comet v3 market
 */
contract SendTokenToExternalAddress is Test {
    QuarkWalletFactory public factory;
    Counter public counter;
    uint256 alicePrivateKey = 0xa11ce;
    address alice = vm.addr(alicePrivateKey);
    uint256 bobPrivateKey = 0xb0b;
    address bob = vm.addr(bobPrivateKey);

    // Contracts address on mainnet
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function setUp() public {
        // Fork setup
        vm.createSelectFork(
            string.concat(
                "https://node-provider.compound.finance/ethereum-mainnet/", vm.envString("NODE_PROVIDER_BYPASS_KEY")
            ),
            18429607 // 2023-10-25 13:24:00 PST
        );
        factory = new QuarkWalletFactory();
    }

    function testTransferERC20TokenToEOA() public {
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        bytes memory terminalScript = new YulHelper().getDeployed(
            "TerminalScript.sol/TerminalScript.json"
        );

        deal(WETH, address(wallet), 10 ether);

        assertEq(IERC20(WETH).balanceOf(address(wallet)), 10 ether);
        assertEq(IERC20(WETH).balanceOf(bob), 0 ether);
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: terminalScript,
            scriptCalldata: abi.encodeWithSelector(TerminalScript.transferERC20Token.selector, WETH, bob, 10 ether),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false,
            isReplayable: false,
            requirements: new uint256[](0)
        });
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(IERC20(WETH).balanceOf(address(wallet)), 0 ether);
        assertEq(IERC20(WETH).balanceOf(bob), 10 ether);
    }

    function testTransferERC20TokenToQuarkWallet() public {
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        QuarkWallet walletBob = QuarkWallet(factory.create(bob, 0));
        bytes memory terminalScript = new YulHelper().getDeployed(
            "TerminalScript.sol/TerminalScript.json"
        );

        deal(WETH, address(wallet), 10 ether);

        assertEq(IERC20(WETH).balanceOf(address(wallet)), 10 ether);
        assertEq(IERC20(WETH).balanceOf(bob), 0 ether);
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: terminalScript,
            scriptCalldata: abi.encodeWithSelector(
                TerminalScript.transferERC20Token.selector, WETH, address(walletBob), 10 ether
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false,
            isReplayable: false,
            requirements: new uint256[](0)
        });
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(IERC20(WETH).balanceOf(address(wallet)), 0 ether);
        assertEq(IERC20(WETH).balanceOf(address(walletBob)), 10 ether);
    }

    function testTransferNativeTokenToEOA() public {
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        bytes memory terminalScript = new YulHelper().getDeployed(
            "TerminalScript.sol/TerminalScript.json"
        );

        deal(address(wallet), 10 ether);

        assertEq(address(wallet).balance, 10 ether);
        assertEq(bob.balance, 0 ether);
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: terminalScript,
            scriptCalldata: abi.encodeWithSelector(TerminalScript.transferNativeToken.selector, bob, 10 ether),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false,
            isReplayable: false,
            requirements: new uint256[](0)
        });
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        wallet.executeQuarkOperation(op, v, r, s);

        // assert on native ETH balance
        assertEq(address(wallet).balance, 0 ether);
        assertEq(bob.balance, 10 ether);
    }

    function testTransferNativeTokenToQuarkWallet() public {
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        QuarkWallet walletBob = QuarkWallet(factory.create(bob, 0));
        bytes memory terminalScript = new YulHelper().getDeployed(
            "TerminalScript.sol/TerminalScript.json"
        );

        deal(address(wallet), 10 ether);

        assertEq(address(wallet).balance, 10 ether);
        assertEq(address(walletBob).balance, 0 ether);
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: terminalScript,
            scriptCalldata: abi.encodeWithSelector(
                TerminalScript.transferNativeToken.selector, address(walletBob), 10 ether
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false,
            isReplayable: false,
            requirements: new uint256[](0)
        });
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        wallet.executeQuarkOperation(op, v, r, s);

        // assert on native ETH balance
        assertEq(address(wallet).balance, 0 ether);
        assertEq(address(walletBob).balance, 10 ether);
    }
}