// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";
import {QuarkWallet, HasSignerExecutor} from "quark-core/src/QuarkWallet.sol";

import {QuarkWalletProxyFactory} from "quark-proxy/src/QuarkWalletProxyFactory.sol";

import {Counter} from "test/lib/Counter.sol";

import {Ethcall} from "quark-core-scripts/src/Ethcall.sol";
import {YulHelper} from "test/lib/YulHelper.sol";
import {Incrementer} from "test/lib/Incrementer.sol";
import {ExecuteOnBehalf} from "test/lib/ExecuteOnBehalf.sol";
import {SignatureHelper} from "test/lib/SignatureHelper.sol";
import {GetMessageDetails} from "test/lib/GetMessageDetails.sol";

contract QuarkWalletProxyFactoryTest is Test {
    event WalletDeploy(address indexed account, address indexed executor, address walletAddress, bytes32 salt);

    CodeJar public codeJar;
    QuarkStateManager public stateManager;
    QuarkWalletProxyFactory public factory;

    uint256 alicePrivateKey = 0xa11ce;
    address alice; // see constructor()
    address bob = address(11);

    constructor() {
        factory = new QuarkWalletProxyFactory(address(new QuarkWallet(new CodeJar(), new QuarkStateManager())));
        console.log("QuarkWalletFactory deployed to: %s", address(factory));

        console.log("wallet implementation address is: %s", factory.walletImplementation());

        codeJar = QuarkWallet(payable(factory.walletImplementation())).codeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        stateManager = QuarkWallet(payable(factory.walletImplementation())).stateManager();
        console.log("QuarkStateManager deployed to: %s", address(stateManager));

        alice = vm.addr(alicePrivateKey);
        console.log("alice address: %s", alice);
    }

    /* ===== sanity checks ===== */

    function testVersion() public {
        assertEq(factory.VERSION(), 1);
    }

    /* ===== wallet creation tests ===== */

    function testCreatesWalletAtDeterministicAddress() public {
        // Non-salted
        vm.expectEmit(true, true, true, true);
        emit WalletDeploy(alice, address(0), factory.walletAddressFor(alice, address(0)), bytes32(0));
        address aliceWallet = factory.create(alice, address(0));
        assertEq(aliceWallet, factory.walletAddressFor(alice, address(0)));

        // Salted
        vm.expectEmit(true, true, true, true);
        emit WalletDeploy(
            alice, address(0), factory.walletAddressForSalt(alice, address(0), bytes32("1")), bytes32("1")
        );
        address aliceWalletSalted = factory.create(alice, address(0), bytes32("1"));
        assertEq(aliceWalletSalted, factory.walletAddressForSalt(alice, address(0), bytes32("1")));
    }

    function testCreateAdditionalWalletWithSalt() public {
        // initial wallet is created
        vm.expectEmit(true, true, true, true);
        emit WalletDeploy(alice, address(0), factory.walletAddressFor(alice, address(0)), bytes32(0));
        factory.create(alice, address(0));

        // NOTE: reverts blow up gas costs astronomically for some reason; they don't need to be measured anyway
        vm.pauseGasMetering();

        // it is created with 0 as salt (and therefore reverts on a repeated attempt)
        vm.expectRevert();
        factory.create(alice, address(0), 0);

        // resume gas metering after the revert to keep the numbers sane and comparable
        vm.resumeGasMetering();

        // but the user can pass in a salt and create additional wallets
        address aliceSaltWallet = factory.create(alice, address(0), bytes32("1"));
        assertEq(aliceSaltWallet, factory.walletAddressForSalt(alice, address(0), bytes32("1")));
    }

    function testCreateRevertsOnRepeat() public {
        vm.expectEmit(true, true, true, true);
        emit WalletDeploy(alice, address(0), factory.walletAddressFor(alice, address(0)), bytes32(0));
        factory.create(alice, address(0));
        vm.expectRevert();
        factory.create(alice, address(0));
    }

    /* ===== create and execute tests ===== */

    function testCreateAndExecuteCreatesWallet() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");
        Counter counter = new Counter();

        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = incrementer;

        address incrementerAddress = codeJar.getCodeAddress(incrementer);
        uint96 nonce = stateManager.nextNonce(factory.walletAddressFor(alice, address(0)));
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptAddress: incrementerAddress,
            scriptSources: scriptSources,
            scriptCalldata: abi.encodeWithSignature("incrementCounter(address)", counter),
            nonce: nonce,
            expiry: block.timestamp + 1000
        });

        // alice signs the operation
        (uint8 v, bytes32 r, bytes32 s) =
            new SignatureHelper().signOpForAddress(alicePrivateKey, factory.walletAddressFor(alice, address(0)), op);

        assertEq(counter.number(), 0);

        // gas: meter execute
        vm.resumeGasMetering();

        // operation is executed
        vm.expectEmit(true, true, true, true);
        // it creates a wallet
        emit WalletDeploy(alice, address(0), factory.walletAddressFor(alice, address(0)), bytes32(0));
        factory.createAndExecute(alice, address(0), op, v, r, s);

        // operation was executed
        assertEq(counter.number(), 3);

        // uses up the operation's nonce
        assertEq(stateManager.isNonceSet(factory.walletAddressFor(alice, address(0)), nonce), true);
    }

    function testCreateAndExecuteWithSalt() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");
        Counter counter = new Counter();

        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = incrementer;

        address incrementerAddress = codeJar.getCodeAddress(incrementer);
        uint96 nonce = stateManager.nextNonce(factory.walletAddressFor(alice, address(0)));
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptAddress: incrementerAddress,
            scriptSources: scriptSources,
            scriptCalldata: abi.encodeWithSignature("incrementCounter(address)", counter),
            nonce: nonce,
            expiry: block.timestamp + 1000
        });

        bytes32 salt = bytes32("salty salt salt");

        // alice signs the operation
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOpForAddress(
            alicePrivateKey, factory.walletAddressForSalt(alice, address(0), salt), op
        );

        assertEq(counter.number(), 0);

        // gas: meter execute
        vm.resumeGasMetering();
        // operation is executed
        vm.expectEmit(true, true, true, true);
        // it creates a wallet (with salt)
        emit WalletDeploy(alice, address(0), factory.walletAddressForSalt(alice, address(0), salt), salt);
        factory.createAndExecute(alice, address(0), salt, op, v, r, s);

        // operation was executed
        assertEq(counter.number(), 3);

        // uses up the operation's nonce
        assertEq(stateManager.isNonceSet(factory.walletAddressForSalt(alice, address(0), salt), nonce), true);
    }

    function testExecuteOnExistingWallet() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");
        Counter counter = new Counter();

        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = incrementer;

        uint96 nonce = stateManager.nextNonce(factory.walletAddressFor(alice, address(0)));
        address incrementerAddress = codeJar.getCodeAddress(incrementer);
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptAddress: incrementerAddress,
            scriptSources: scriptSources,
            scriptCalldata: abi.encodeWithSignature("incrementCounter(address)", counter),
            nonce: nonce,
            expiry: block.timestamp + 1000
        });

        // alice signs the operation
        (uint8 v, bytes32 r, bytes32 s) =
            new SignatureHelper().signOpForAddress(alicePrivateKey, factory.walletAddressFor(alice, address(0)), op);

        assertEq(counter.number(), 0);

        // gas: meter create, createAndExecute
        vm.resumeGasMetering();

        // the wallet is deployed
        vm.expectEmit(true, true, true, true);
        emit WalletDeploy(alice, address(0), factory.walletAddressFor(alice, address(0)), bytes32(0));
        factory.create(alice, address(0));

        // operation is executed
        factory.createAndExecute(alice, address(0), op, v, r, s);

        // operation was executed
        assertEq(counter.number(), 3);

        // uses up the operation's nonce
        assertEq(stateManager.isNonceSet(factory.walletAddressFor(alice, address(0)), nonce), true);
    }

    /* ===== msg.value and msg.sender tests ===== */

    function testCreateAndExecuteSetsMsgSender() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory getMessageDetails = new YulHelper().getCode("GetMessageDetails.sol/GetMessageDetails.json");
        address aliceWallet = factory.walletAddressFor(alice, address(0));
        uint96 nonce = stateManager.nextNonce(aliceWallet);

        address getMessageDetailsAddress = codeJar.getCodeAddress(getMessageDetails);

        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = getMessageDetails;

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptAddress: getMessageDetailsAddress,
            scriptSources: scriptSources,
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
        bytes memory result = factory.createAndExecute(alice, address(0), op, v, r, s);

        (address msgSender, uint256 msgValue) = abi.decode(result, (address, uint256));
        assertEq(msgSender, address(aliceWallet));
        assertEq(msgValue, 0);

        // uses up the operation's nonce
        assertEq(stateManager.isNonceSet(aliceWallet, nonce), true);
    }

    function testCreateAndExecuteWithSaltSetsMsgSender() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory getMessageDetails = new YulHelper().getCode("GetMessageDetails.sol/GetMessageDetails.json");
        bytes32 salt = bytes32("salty salt salt");
        address aliceWallet = factory.walletAddressForSalt(alice, address(0), salt);
        uint96 nonce = stateManager.nextNonce(aliceWallet);
        address getMessageDetailsAddress = codeJar.getCodeAddress(getMessageDetails);

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptAddress: getMessageDetailsAddress,
            scriptSources: new bytes[](0),
            scriptCalldata: abi.encodeWithSignature("getMsgSenderAndValue()"),
            nonce: nonce,
            expiry: block.timestamp + 1000
        });
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOpForAddress(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();

        // we didn't include the script source in scriptSources and we never deployed it!
        vm.expectRevert(QuarkWallet.EmptyCode.selector);
        factory.createAndExecute(alice, address(0), salt, op, v, r, s);

        // gas: do not meter set-up
        vm.pauseGasMetering();

        // but if we do add it...
        op.scriptSources = new bytes[](1);
        op.scriptSources[0] = getMessageDetails;
        (v, r, s) = new SignatureHelper().signOpForAddress(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();

        // then the script gets deployed and the operation is executed
        vm.expectEmit(true, true, true, true);
        // it creates a wallet
        emit WalletDeploy(alice, address(0), aliceWallet, salt);
        bytes memory result = factory.createAndExecute(alice, address(0), salt, op, v, r, s);

        (address msgSender, uint256 msgValue) = abi.decode(result, (address, uint256));
        assertEq(msgSender, address(aliceWallet));
        assertEq(msgValue, 0);

        // uses up the operation's nonce
        assertEq(stateManager.isNonceSet(aliceWallet, nonce), true);
    }

    /* ===== default wallet executor role tests ===== */

    function testExecutorSetInCreate() public {
        QuarkWallet aliceWallet = QuarkWallet(factory.create(alice, address(0xabc)));
        assertEq(HasSignerExecutor(address(aliceWallet)).executor(), address(0xabc));
    }

    function testExecutorIsOtherWallet() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();

        bytes memory ethcall = new YulHelper().getCode("Ethcall.sol/Ethcall.json");
        address ethcallAddress = codeJar.saveCode(ethcall);

        bytes memory executeOnBehalf = new YulHelper().getCode("ExecuteOnBehalf.sol/ExecuteOnBehalf.json");

        Counter counter = new Counter();

        // construct a primary wallet with one sub-wallet
        QuarkWallet aliceWalletPrimary = QuarkWallet(factory.create(alice, address(0)));
        QuarkWallet aliceWalletSecondary = QuarkWallet(factory.create(alice, address(aliceWalletPrimary), bytes32("1")));

        address executeOnBehalfAddress = codeJar.getCodeAddress(executeOnBehalf);

        // NOTE: necessary to pass this into scriptSources or it will be EmptyCode()!
        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = executeOnBehalf;

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptAddress: executeOnBehalfAddress,
            scriptSources: scriptSources,
            scriptCalldata: abi.encodeWithSignature(
                "run(address,uint96,address,bytes)",
                address(aliceWalletSecondary),
                stateManager.nextNonce(address(aliceWalletSecondary)),
                ethcallAddress,
                abi.encodeWithSignature(
                    "run(address,bytes,uint256)", address(counter), abi.encodeWithSignature("increment(uint256)", 7), 0
                )
                ),
            nonce: stateManager.nextNonce(address(aliceWalletPrimary)),
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
