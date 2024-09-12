// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkNonceManager} from "quark-core/src/QuarkNonceManager.sol";
import {QuarkWallet, IHasSignerExecutor} from "quark-core/src/QuarkWallet.sol";

import {QuarkWalletProxyFactory} from "quark-proxy/src/QuarkWalletProxyFactory.sol";

import {QuarkOperationHelper} from "test/lib/QuarkOperationHelper.sol";

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
    QuarkNonceManager public nonceManager;
    QuarkWalletProxyFactory public factory;

    uint256 alicePrivateKey = 0xa11ce;
    address alice; // see constructor()
    address bob = address(11);

    constructor() {
        factory = new QuarkWalletProxyFactory(address(new QuarkWallet(new CodeJar(), new QuarkNonceManager())));
        console.log("QuarkWalletFactory deployed to: %s", address(factory));

        console.log("wallet implementation address is: %s", factory.walletImplementation());

        codeJar = QuarkWallet(payable(factory.walletImplementation())).codeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        nonceManager = QuarkWallet(payable(factory.walletImplementation())).nonceManager();
        console.log("QuarkNonceManager deployed to: %s", address(nonceManager));

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
        bytes32 nonce = new QuarkOperationHelper().semiRandomNonce(
            nonceManager, QuarkWallet(payable(factory.walletAddressFor(alice, address(0))))
        );
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptAddress: incrementerAddress,
            scriptSources: scriptSources,
            scriptCalldata: abi.encodeWithSignature("incrementCounter(address)", counter),
            nonce: nonce,
            isReplayable: false,
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
        assertEq(
            nonceManager.submissions(factory.walletAddressFor(alice, address(0)), nonce), bytes32(type(uint256).max)
        );
    }

    function testCreateAndExecuteWithSalt() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");
        Counter counter = new Counter();

        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = incrementer;

        address incrementerAddress = codeJar.getCodeAddress(incrementer);
        bytes32 nonce = new QuarkOperationHelper().semiRandomNonce(
            nonceManager, QuarkWallet(payable(factory.walletAddressFor(alice, address(0))))
        );
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptAddress: incrementerAddress,
            scriptSources: scriptSources,
            scriptCalldata: abi.encodeWithSignature("incrementCounter(address)", counter),
            nonce: nonce,
            isReplayable: false,
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
        assertEq(
            nonceManager.submissions(factory.walletAddressForSalt(alice, address(0), salt), nonce),
            bytes32(type(uint256).max)
        );
    }

    function testExecuteOnExistingWallet() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");
        Counter counter = new Counter();

        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = incrementer;

        bytes32 nonce = new QuarkOperationHelper().semiRandomNonce(
            nonceManager, QuarkWallet(payable(factory.walletAddressFor(alice, address(0))))
        );
        address incrementerAddress = codeJar.getCodeAddress(incrementer);
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptAddress: incrementerAddress,
            scriptSources: scriptSources,
            scriptCalldata: abi.encodeWithSignature("incrementCounter(address)", counter),
            nonce: nonce,
            isReplayable: false,
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
        assertEq(
            nonceManager.submissions(factory.walletAddressFor(alice, address(0)), nonce), bytes32(type(uint256).max)
        );
    }

    /* ===== create and execute MultiQuarkOperation tests ===== */

    function testCreateAndExecuteMultiCreatesWallet() public {
        // gas: disable metering except while executing operations
        vm.pauseGasMetering();

        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");
        Counter counter = new Counter();
        assertEq(counter.number(), 0);

        vm.startPrank(address(alice));

        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = incrementer;

        address incrementerAddress = codeJar.getCodeAddress(incrementer);
        address aliceWalletAddress = factory.walletAddressFor(alice, address(0));
        bytes32 nonce =
            new QuarkOperationHelper().semiRandomNonce(nonceManager, QuarkWallet(payable(aliceWalletAddress)));
        QuarkWallet.QuarkOperation memory op1 = QuarkWallet.QuarkOperation({
            scriptAddress: incrementerAddress,
            scriptSources: scriptSources,
            scriptCalldata: abi.encodeWithSignature("incrementCounter(address)", counter),
            nonce: nonce,
            isReplayable: false,
            expiry: block.timestamp + 1000
        });
        bytes32 op1Digest = new SignatureHelper().opDigest(aliceWalletAddress, op1);

        QuarkWallet.QuarkOperation memory op2 = QuarkWallet.QuarkOperation({
            scriptAddress: incrementerAddress,
            scriptSources: scriptSources,
            scriptCalldata: abi.encodeWithSignature("incrementCounter(address)", counter),
            nonce: new QuarkOperationHelper().incrementNonce(nonce),
            isReplayable: false,
            expiry: block.timestamp + 1000
        });
        op2.nonce = new QuarkOperationHelper().incrementNonce(op1.nonce);
        bytes32 op2Digest = new SignatureHelper().opDigest(aliceWalletAddress, op2);

        bytes32[] memory opDigests = new bytes32[](2);
        opDigests[0] = op1Digest;
        opDigests[1] = op2Digest;
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signMultiOp(alicePrivateKey, opDigests);

        vm.resumeGasMetering();
        // call once
        vm.expectEmit(true, true, true, true);
        // it creates a wallet
        emit WalletDeploy(alice, address(0), aliceWalletAddress, bytes32(0));
        factory.createAndExecuteMulti(alice, address(0), op1, opDigests, v, r, s);

        assertEq(counter.number(), 3);
        assertEq(nonceManager.submissions(aliceWalletAddress, op1.nonce), bytes32(type(uint256).max));

        // call a second time
        factory.createAndExecuteMulti(alice, address(0), op2, opDigests, v, r, s);

        assertEq(counter.number(), 6);
        assertEq(nonceManager.submissions(aliceWalletAddress, op2.nonce), bytes32(type(uint256).max));
    }

    function testCreateAndExecuteMultiWithSalt() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");
        Counter counter = new Counter();

        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = incrementer;

        address incrementerAddress = codeJar.getCodeAddress(incrementer);
        bytes32 salt = bytes32("salty salt salt");
        address aliceWalletAddress = factory.walletAddressForSalt(alice, address(0), salt);
        bytes32 nonce =
            new QuarkOperationHelper().semiRandomNonce(nonceManager, QuarkWallet(payable(aliceWalletAddress)));
        QuarkWallet.QuarkOperation memory op1 = QuarkWallet.QuarkOperation({
            scriptAddress: incrementerAddress,
            scriptSources: scriptSources,
            scriptCalldata: abi.encodeWithSignature("incrementCounter(address)", counter),
            nonce: nonce,
            isReplayable: false,
            expiry: block.timestamp + 1000
        });
        bytes32 op1Digest = new SignatureHelper().opDigest(aliceWalletAddress, op1);

        QuarkWallet.QuarkOperation memory op2 = QuarkWallet.QuarkOperation({
            scriptAddress: incrementerAddress,
            scriptSources: scriptSources,
            scriptCalldata: abi.encodeWithSignature("incrementCounter(address)", counter),
            nonce: new QuarkOperationHelper().incrementNonce(nonce),
            isReplayable: false,
            expiry: block.timestamp + 1000
        });
        op2.nonce = new QuarkOperationHelper().incrementNonce(op1.nonce);
        bytes32 op2Digest = new SignatureHelper().opDigest(aliceWalletAddress, op2);

        bytes32[] memory opDigests = new bytes32[](2);
        opDigests[0] = op1Digest;
        opDigests[1] = op2Digest;
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signMultiOp(alicePrivateKey, opDigests);

        vm.resumeGasMetering();
        // call once
        vm.expectEmit(true, true, true, true);
        // it creates a wallet (with salt)
        emit WalletDeploy(alice, address(0), aliceWalletAddress, salt);
        factory.createAndExecuteMulti(alice, address(0), salt, op1, opDigests, v, r, s);

        assertEq(counter.number(), 3);
        assertEq(nonceManager.submissions(aliceWalletAddress, op1.nonce), bytes32(type(uint256).max));

        // call a second time
        factory.createAndExecuteMulti(alice, address(0), salt, op2, opDigests, v, r, s);

        assertEq(counter.number(), 6);
        assertEq(nonceManager.submissions(aliceWalletAddress, op2.nonce), bytes32(type(uint256).max));
    }

    function testExecuteMultiOnExistingWallet() public {
        // gas: disable metering except while executing operations
        vm.pauseGasMetering();

        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");
        Counter counter = new Counter();
        assertEq(counter.number(), 0);

        vm.startPrank(address(alice));

        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = incrementer;

        address incrementerAddress = codeJar.getCodeAddress(incrementer);
        address aliceWalletAddress = factory.walletAddressFor(alice, address(0));
        bytes32 nonce =
            new QuarkOperationHelper().semiRandomNonce(nonceManager, QuarkWallet(payable(aliceWalletAddress)));
        QuarkWallet.QuarkOperation memory op1 = QuarkWallet.QuarkOperation({
            scriptAddress: incrementerAddress,
            scriptSources: scriptSources,
            scriptCalldata: abi.encodeWithSignature("incrementCounter(address)", counter),
            nonce: nonce,
            isReplayable: false,
            expiry: block.timestamp + 1000
        });
        bytes32 op1Digest = new SignatureHelper().opDigest(aliceWalletAddress, op1);

        QuarkWallet.QuarkOperation memory op2 = QuarkWallet.QuarkOperation({
            scriptAddress: incrementerAddress,
            scriptSources: scriptSources,
            scriptCalldata: abi.encodeWithSignature("incrementCounter(address)", counter),
            nonce: new QuarkOperationHelper().incrementNonce(nonce),
            isReplayable: false,
            expiry: block.timestamp + 1000
        });
        op2.nonce = new QuarkOperationHelper().incrementNonce(op1.nonce);
        bytes32 op2Digest = new SignatureHelper().opDigest(aliceWalletAddress, op2);

        bytes32[] memory opDigests = new bytes32[](2);
        opDigests[0] = op1Digest;
        opDigests[1] = op2Digest;
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signMultiOp(alicePrivateKey, opDigests);

        // gas: meter create, createAndExecute
        vm.resumeGasMetering();

        // the wallet is deployed
        vm.expectEmit(true, true, true, true);
        emit WalletDeploy(alice, address(0), aliceWalletAddress, bytes32(0));
        factory.create(alice, address(0));

        // call once
        factory.createAndExecuteMulti(alice, address(0), op1, opDigests, v, r, s);

        assertEq(counter.number(), 3);
        assertEq(nonceManager.submissions(aliceWalletAddress, op1.nonce), bytes32(type(uint256).max));

        // call a second time
        factory.createAndExecuteMulti(alice, address(0), op2, opDigests, v, r, s);

        assertEq(counter.number(), 6);
        assertEq(nonceManager.submissions(aliceWalletAddress, op2.nonce), bytes32(type(uint256).max));
    }

    /* ===== msg.value and msg.sender tests ===== */

    function testCreateAndExecuteSetsMsgSender() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory getMessageDetails = new YulHelper().getCode("GetMessageDetails.sol/GetMessageDetails.json");
        address aliceWallet = factory.walletAddressFor(alice, address(0));
        bytes32 nonce = new QuarkOperationHelper().semiRandomNonce(nonceManager, QuarkWallet(payable(aliceWallet)));

        address getMessageDetailsAddress = codeJar.getCodeAddress(getMessageDetails);

        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = getMessageDetails;

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptAddress: getMessageDetailsAddress,
            scriptSources: scriptSources,
            scriptCalldata: abi.encodeWithSignature("getMsgSenderAndValue()"),
            nonce: nonce,
            isReplayable: false,
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
        assertEq(nonceManager.submissions(aliceWallet, nonce), bytes32(type(uint256).max));
    }

    function testCreateAndExecuteWithSaltSetsMsgSender() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory getMessageDetails = new YulHelper().getCode("GetMessageDetails.sol/GetMessageDetails.json");
        bytes32 salt = bytes32("salty salt salt");
        address aliceWallet = factory.walletAddressForSalt(alice, address(0), salt);
        bytes32 nonce = new QuarkOperationHelper().semiRandomNonce(nonceManager, QuarkWallet(payable(aliceWallet)));
        address getMessageDetailsAddress = codeJar.getCodeAddress(getMessageDetails);

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptAddress: getMessageDetailsAddress,
            scriptSources: new bytes[](0),
            scriptCalldata: abi.encodeWithSignature("getMsgSenderAndValue()"),
            nonce: nonce,
            isReplayable: false,
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
        assertEq(nonceManager.submissions(aliceWallet, nonce), bytes32(type(uint256).max));
    }

    /* ===== default wallet executor role tests ===== */

    function testExecutorSetInCreate() public {
        QuarkWallet aliceWallet = QuarkWallet(factory.create(alice, address(0xabc)));
        assertEq(IHasSignerExecutor(address(aliceWallet)).executor(), address(0xabc));
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
                "run(address,bytes32,address,bytes)",
                address(aliceWalletSecondary),
                new QuarkOperationHelper().semiRandomNonce(nonceManager, aliceWalletSecondary),
                ethcallAddress,
                abi.encodeWithSignature(
                    "run(address,bytes,uint256)", address(counter), abi.encodeWithSignature("increment(uint256)", 7), 0
                )
            ),
            nonce: new QuarkOperationHelper().semiRandomNonce(nonceManager, aliceWalletPrimary),
            isReplayable: false,
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
