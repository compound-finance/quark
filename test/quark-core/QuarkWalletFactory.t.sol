// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {Counter} from "test/lib/Counter.sol";
import {SignatureHelper} from "test/lib/SignatureHelper.sol";
import {YulHelper} from "test/lib/YulHelper.sol";

import {CodeJar} from "quark-core/src/CodeJar.sol";
import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkWalletFactory} from "quark-core/src/QuarkWalletFactory.sol";

import "quark-core-scripts/src/Ethcall.sol";

contract QuarkWalletFactoryTest is Test {
    event WalletDeploy(address indexed account, address indexed executor, address walletAddress, bytes32 salt);

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

    /* ===== sanity checks ===== */

    function testVersion() public {
        assertEq(factory.VERSION(), 1);
    }

    function testCreatesCodejar() public {
        assertNotEq(address(factory.codeJar()), address(0));
    }

    // TODO: testCreatesStateManager()

    /* ===== wallet creation tests ===== */

    function testCreatesWalletAtDeterministicAddress() public {
        // Non-salted
        vm.expectEmit(true, true, true, true);
        emit WalletDeploy(alice, address(0), factory.walletAddressForSigner(alice), bytes32(0));
        address aliceWallet = factory.create(alice);
        assertEq(aliceWallet, factory.walletAddressForSigner(alice));

        // Salted
        vm.expectEmit(true, true, true, true);
        emit WalletDeploy(
            alice,
            factory.walletAddressForSigner(alice),
            factory.walletAddressForSignerWithSalt(alice, bytes32("1")),
            bytes32("1")
        );
        address aliceWalletSalted = factory.create(alice, bytes32("1"));
        assertEq(aliceWalletSalted, factory.walletAddressForSignerWithSalt(alice, bytes32("1")));
    }

    function testCreateAdditionalWalletWithSalt() public {
        // inital wallet is created
        vm.expectEmit(true, true, true, true);
        emit WalletDeploy(alice, address(0), factory.walletAddressForSigner(alice), bytes32(0));
        factory.create(alice);

        // it is created with 0 as salt (and therefore reverts on a repeated attempt)
        vm.expectRevert();
        factory.create(alice, 0);

        // but the user can pass in a salt and create additional wallets
        address aliceSaltWallet = factory.create(alice, bytes32("1"));
        assertEq(aliceSaltWallet, factory.walletAddressForSignerWithSalt(alice, bytes32("1")));
    }

    function testCreateRevertsOnRepeat() public {
        vm.expectEmit(true, true, true, true);
        emit WalletDeploy(alice, address(0), factory.walletAddressForSigner(alice), bytes32(0));
        factory.create(alice);
        vm.expectRevert();
        factory.create(alice);
    }

    /* ===== create and execute tests ===== */

    function testCreateAndExecuteCreatesWallet() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");

        uint96 nonce = factory.stateManager().nextNonce(factory.walletAddressForSigner(alice));
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptAddress: address(0),
            scriptSource: incrementer,
            scriptCalldata: abi.encodeWithSignature("incrementCounter(address)", counter),
            nonce: nonce,
            expiry: block.timestamp + 1000
        });

        // alice signs the operation
        (uint8 v, bytes32 r, bytes32 s) =
            new SignatureHelper().signOpForAddress(alicePrivateKey, factory.walletAddressForSigner(alice), op);

        assertEq(counter.number(), 0);

        // gas: meter execute
        vm.resumeGasMetering();

        // operation is executed
        vm.expectEmit(true, true, true, true);
        // it creates a wallet
        emit WalletDeploy(alice, address(0), factory.walletAddressForSigner(alice), bytes32(0));
        factory.createAndExecute(alice, op, v, r, s);

        // operation was executed
        assertEq(counter.number(), 3);

        // uses up the operation's nonce
        assertEq(factory.stateManager().isNonceSet(factory.walletAddressForSigner(alice), nonce), true);
    }

    function testCreateAndExecuteWithSalt() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");

        uint96 nonce = factory.stateManager().nextNonce(factory.walletAddressForSigner(alice));
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptAddress: address(0),
            scriptSource: incrementer,
            scriptCalldata: abi.encodeWithSignature("incrementCounter(address)", counter),
            nonce: nonce,
            expiry: block.timestamp + 1000
        });

        bytes32 salt = bytes32("salty salt salt");

        // alice signs the operation
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOpForAddress(
            alicePrivateKey, factory.walletAddressForSignerWithSalt(alice, salt), op
        );

        assertEq(counter.number(), 0);

        // gas: meter execute
        vm.resumeGasMetering();
        // operation is executed
        vm.expectEmit(true, true, true, true);
        // it creates a wallet (with salt)
        emit WalletDeploy(
            alice, factory.walletAddressForSigner(alice), factory.walletAddressForSignerWithSalt(alice, salt), salt
        );
        factory.createAndExecute(alice, salt, op, v, r, s);

        // operation was executed
        assertEq(counter.number(), 3);

        // uses up the operation's nonce
        assertEq(factory.stateManager().isNonceSet(factory.walletAddressForSignerWithSalt(alice, salt), nonce), true);
    }

    function testExecuteOnExistingWallet() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");

        uint96 nonce = factory.stateManager().nextNonce(factory.walletAddressForSigner(alice));
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptAddress: address(0),
            scriptSource: incrementer,
            scriptCalldata: abi.encodeWithSignature("incrementCounter(address)", counter),
            nonce: nonce,
            expiry: block.timestamp + 1000
        });

        // alice signs the operation
        (uint8 v, bytes32 r, bytes32 s) =
            new SignatureHelper().signOpForAddress(alicePrivateKey, factory.walletAddressForSigner(alice), op);

        assertEq(counter.number(), 0);

        // gas: meter create, createAndExecute
        vm.resumeGasMetering();

        // the wallet is deployed
        vm.expectEmit(true, true, true, true);
        emit WalletDeploy(alice, address(0), factory.walletAddressForSigner(alice), bytes32(0));
        factory.create(alice);

        // operation is executed
        factory.createAndExecute(alice, op, v, r, s);

        // operation was executed
        assertEq(counter.number(), 3);

        // uses up the operation's nonce
        assertEq(factory.stateManager().isNonceSet(factory.walletAddressForSigner(alice), nonce), true);
    }

    /* ===== msg.value and msg.sender tests ===== */

    function testCreateAndExecuteSetsMsgSender() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory getMessageDetails = new YulHelper().getDeployed("GetMessageDetails.sol/GetMessageDetails.json");
        address aliceWallet = factory.walletAddressForSigner(alice);
        uint96 nonce = factory.stateManager().nextNonce(aliceWallet);
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptAddress: address(0),
            scriptSource: getMessageDetails,
            scriptCalldata: abi.encodeWithSignature("getMsgSenderAndValue()"),
            nonce: nonce,
            expiry: block.timestamp + 1000
        });
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOpForAddress(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();

        // operation is executed
        vm.expectEmit(true, true, true, true);
        // it creates a wallet
        emit WalletDeploy(alice, address(0), aliceWallet, bytes32(0));
        bytes memory result = factory.createAndExecute(alice, op, v, r, s);

        (address msgSender, uint256 msgValue) = abi.decode(result, (address, uint256));
        assertEq(msgSender, address(aliceWallet));
        assertEq(msgValue, 0);

        // uses up the operation's nonce
        assertEq(factory.stateManager().isNonceSet(aliceWallet, nonce), true);
    }

    function testCreateAndExecuteWithSaltSetsMsgSender() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory getMessageDetails = new YulHelper().getDeployed("GetMessageDetails.sol/GetMessageDetails.json");
        bytes32 salt = bytes32("salty salt salt");
        address aliceWallet = factory.walletAddressForSignerWithSalt(alice, salt);
        uint96 nonce = factory.stateManager().nextNonce(aliceWallet);
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptAddress: address(0),
            scriptSource: getMessageDetails,
            scriptCalldata: abi.encodeWithSignature("getMsgSenderAndValue()"),
            nonce: nonce,
            expiry: block.timestamp + 1000
        });
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOpForAddress(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();

        // operation is executed
        vm.expectEmit(true, true, true, true);
        // it creates a wallet
        emit WalletDeploy(alice, factory.walletAddressForSigner(alice), aliceWallet, salt);
        bytes memory result = factory.createAndExecute(alice, salt, op, v, r, s);

        (address msgSender, uint256 msgValue) = abi.decode(result, (address, uint256));
        assertEq(msgSender, address(aliceWallet));
        assertEq(msgValue, 0);

        // uses up the operation's nonce
        assertEq(factory.stateManager().isNonceSet(aliceWallet, nonce), true);
    }

    /* ===== default wallet executor role tests ===== */

    function testDefaultWalletHasNoExecutor() public {
        QuarkWallet aliceWallet = QuarkWallet(factory.create(alice));
        assertEq(aliceWallet.executor(), address(0));
    }

    function testDefaultWalletIsSubwalletExecutor() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();

        bytes memory ethcall = new YulHelper().getDeployed("Ethcall.sol/Ethcall.json");
        address ethcallAddress = factory.codeJar().saveCode(ethcall);

        bytes memory executeOnBehalf = new YulHelper().getDeployed("ExecuteOnBehalf.sol/ExecuteOnBehalf.json");

        // construct a primary wallet with one sub-wallet
        QuarkWallet aliceWalletPrimary = QuarkWallet(factory.create(alice));
        QuarkWallet aliceWalletSecondary = QuarkWallet(factory.create(alice, bytes32("1")));

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptAddress: address(0),
            scriptSource: executeOnBehalf,
            scriptCalldata: abi.encodeWithSignature(
                "run(address,uint96,address,bytes)",
                address(aliceWalletSecondary),
                factory.stateManager().nextNonce(address(aliceWalletSecondary)),
                ethcallAddress,
                abi.encodeWithSignature(
                    "run(address,bytes,uint256)", address(counter), abi.encodeWithSignature("increment(uint256)", 7), 0
                )
                ),
            nonce: factory.stateManager().nextNonce(address(aliceWalletPrimary)),
            expiry: block.timestamp + 1000
        });
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWalletPrimary, op);

        // gas: meter execute
        vm.resumeGasMetering();
        assertEq(counter.number(), 0);
        aliceWalletPrimary.executeQuarkOperation(op, v, r, s);
        assertEq(counter.number(), 7);
    }
}