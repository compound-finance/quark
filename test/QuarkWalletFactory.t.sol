// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {Counter} from "./lib/Counter.sol";
import {SignatureHelper} from "./lib/SignatureHelper.sol";
import {YulHelper} from "./lib/YulHelper.sol";

import {CodeJar} from "../src/CodeJar.sol";
import {QuarkWallet} from "../src/QuarkWallet.sol";
import {QuarkWalletFactory} from "../src/QuarkWalletFactory.sol";

contract QuarkWalletFactoryTest is Test {
    event WalletDeploy(address indexed account, address indexed walletAddress, bytes32 salt);

    QuarkWalletFactory public factory;
    Counter public counter;

    uint256 alicePrivateKey = 0xa11ce;
    address alice; // see setup()
    address bob = address(11);

    constructor() {
        factory = new QuarkWalletFactory();
        console.log("QuarkWalletFactory deployed to: %s", address(factory));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));

        alice = vm.addr(alicePrivateKey);
    }

    function testVersion() public {
        assertEq(factory.VERSION(), 1);
    }

    function testCreatesCodejar() public {
        assertNotEq(address(factory.codeJar()), address(0));
    }

    function testCreatesWalletAtDeterministicAddress() public {
        vm.expectEmit(true, true, true, true);
        emit WalletDeploy(alice, factory.walletAddressForAccount(alice), bytes32(0));
        address aliceWallet = factory.create(alice);
        assertEq(aliceWallet, factory.walletAddressForAccount(alice));
    }

    function testCreateRevertsOnRepeat() public {
        vm.expectEmit(true, true, true, true);
        emit WalletDeploy(alice, factory.walletAddressForAccount(alice), bytes32(0));
        factory.create(alice);
        vm.expectRevert();
        factory.create(alice);
    }

    function testCreateAdditionalWalletWithSalt() public {
        // inital wallet is created
        vm.expectEmit(true, true, true, true);
        emit WalletDeploy(alice, factory.walletAddressForAccount(alice), bytes32(0));
        factory.create(alice);

        // it is created with 0 as salt (and therefore reverts on a repeated attempt)
        vm.expectRevert();
        factory.create(alice, 0);

        // but the user can pass in a salt and create additional wallets
        address aliceSaltWallet = factory.create(alice, bytes32("1"));
        assertEq(aliceSaltWallet, factory.walletAddressForAccount(alice, bytes32("1")));
    }

    function testCreateAndExecuteCreatesWallet() public {
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");

        uint256 nonce = factory.storageManager().nextUnusedNonce(factory.walletAddressForAccount(alice));
        uint256[] memory requirements;
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: incrementer,
            scriptCalldata: abi.encodeWithSignature("incrementCounter(address)", counter),
            nonce: nonce,
            expiry: block.timestamp + 1000,
            allowCallback: false,
            requirements: requirements
        });

        // alice signs the operation
        (uint8 v, bytes32 r, bytes32 s) =
            new SignatureHelper().signOpForAddress(alicePrivateKey, factory.walletAddressForAccount(alice), op);

        assertEq(counter.number(), 0);

        // operation is executed
        vm.expectEmit(true, true, true, true);
        // it creates a wallet
        emit WalletDeploy(alice, factory.walletAddressForAccount(alice), bytes32(0));
        factory.createAndExecute(alice, op, v, r, s);

        // operation was executed
        assertEq(counter.number(), 3);

        // uses up the operation's nonce
        assertEq(factory.storageManager().isNonceSet(factory.walletAddressForAccount(alice), nonce), true);
    }

    function testCreateAndExecuteWithSalt() public {
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");

        uint256 nonce = factory.storageManager().nextUnusedNonce(factory.walletAddressForAccount(alice));
        uint256[] memory requirements;
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: incrementer,
            scriptCalldata: abi.encodeWithSignature("incrementCounter(address)", counter),
            nonce: nonce,
            expiry: block.timestamp + 1000,
            allowCallback: false,
            requirements: requirements
        });

        bytes32 salt = bytes32("salty salt salt");

        // alice signs the operation
        (uint8 v, bytes32 r, bytes32 s) =
            new SignatureHelper().signOpForAddress(alicePrivateKey, factory.walletAddressForAccount(alice, salt), op);

        assertEq(counter.number(), 0);

        // operation is executed
        vm.expectEmit(true, true, true, true);
        // it creates a wallet (with salt)
        emit WalletDeploy(alice, factory.walletAddressForAccount(alice, salt), salt);
        factory.createAndExecute(alice, salt, op, v, r, s);

        // operation was executed
        assertEq(counter.number(), 3);

        // uses up the operation's nonce
        assertEq(factory.storageManager().isNonceSet(factory.walletAddressForAccount(alice, salt), nonce), true);
    }

    function testExecuteOnExistingWallet() public {
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");

        uint256 nonce = factory.storageManager().nextUnusedNonce(factory.walletAddressForAccount(alice));
        uint256[] memory requirements;
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: incrementer,
            scriptCalldata: abi.encodeWithSignature("incrementCounter(address)", counter),
            nonce: nonce,
            expiry: block.timestamp + 1000,
            allowCallback: false,
            requirements: requirements
        });

        // alice signs the operation
        (uint8 v, bytes32 r, bytes32 s) =
            new SignatureHelper().signOpForAddress(alicePrivateKey, factory.walletAddressForAccount(alice), op);

        assertEq(counter.number(), 0);

        // the wallet is deployed
        vm.expectEmit(true, true, true, true);
        emit WalletDeploy(alice, factory.walletAddressForAccount(alice), bytes32(0));
        factory.create(alice);

        // operation is executed
        factory.createAndExecute(alice, op, v, r, s);

        // operation was executed
        assertEq(counter.number(), 3);

        // uses up the operation's nonce
        assertEq(factory.storageManager().isNonceSet(factory.walletAddressForAccount(alice), nonce), true);
    }
}
