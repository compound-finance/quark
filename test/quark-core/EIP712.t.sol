// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.27;

import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/console.sol";

import {Test} from "forge-std/Test.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

import {QuarkNonceManager} from "quark-core/src/QuarkNonceManager.sol";
import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkWalletStandalone} from "quark-core/src/QuarkWalletStandalone.sol";

import {Counter} from "test/lib/Counter.sol";
import {Incrementer} from "test/lib/Incrementer.sol";
import {ExecuteWithRequirements} from "test/lib/ExecuteWithRequirements.sol";

import {YulHelper} from "test/lib/YulHelper.sol";
import {SignatureHelper} from "test/lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "test/lib/QuarkOperationHelper.sol";

contract EIP712Test is Test {
    CodeJar public codeJar;
    Counter public counter;
    QuarkWallet public wallet;
    QuarkNonceManager public nonceManager;

    uint256 alicePrivateKey = 0xa11ce;
    address alice; // see setup()
    address bob = address(11); // 0x00...b

    function setUp() public {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        nonceManager = new QuarkNonceManager();
        console.log("QuarkNonceManager deployed to: %s", address(nonceManager));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));

        alice = vm.addr(alicePrivateKey);
        wallet = new QuarkWalletStandalone(alice, address(0), codeJar, nonceManager);
    }

    function incrementCounterOperation(QuarkWallet targetWallet) public returns (QuarkWallet.QuarkOperation memory) {
        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");

        return new QuarkOperationHelper().newBasicOpWithCalldata(
            targetWallet,
            incrementer,
            abi.encodeWithSignature("incrementCounter(address)", counter),
            ScriptType.ScriptSource
        );
    }

    function testExecuteQuarkOperation() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        assertEq(counter.number(), 0);

        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(wallet);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);

        // counter has incremented
        assertEq(counter.number(), 3);

        // nonce is spent
        assertEq(nonceManager.submissions(address(wallet), op.nonce), bytes32(type(uint256).max));
    }

    function testRevertsForBadCode() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        assertEq(counter.number(), 0);

        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(wallet);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // bad actor modifies script source to selfdestruct the wallet
        op.scriptSources = new bytes[](1);
        op.scriptSources[0] = bytes(hex"6000ff");

        // gas: meter execute
        vm.resumeGasMetering();

        // submitter calls executeQuarkOperation with the signed op, but they manipulate the code
        vm.expectRevert(QuarkWallet.BadSignatory.selector);
        wallet.executeQuarkOperation(op, v, r, s);

        // counter is unchanged
        assertEq(counter.number(), 0);

        // nonce is not spent
        assertEq(nonceManager.submissions(address(wallet), op.nonce), bytes32(uint256(0)));
    }

    function testStructHash() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        assertEq(counter.number(), 0);

        address wallet_ = address(0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9);
        bytes memory incrementer =
            hex"608060405234801561001057600080fd5b506102a7806100206000396000f3fe608060405234801561001057600080fd5b50600436106100365760003560e01c80636b582b7614610056578063e5910ae714610069575b73f62849f9a0b5bf2913b396098f7c7019b51a820a61005481610077565b005b610054610064366004610230565b610173565b610054610077366004610230565b806001600160a01b031663d09de08a6040518163ffffffff1660e01b8152600401600060405180830381600087803b1580156100b257600080fd5b505af11580156100c6573d6000803e3d6000fd5b50505050806001600160a01b031663d09de08a6040518163ffffffff1660e01b8152600401600060405180830381600087803b15801561010557600080fd5b505af1158015610119573d6000803e3d6000fd5b50505050806001600160a01b031663d09de08a6040518163ffffffff1660e01b8152600401600060405180830381600087803b15801561015857600080fd5b505af115801561016c573d6000803e3d6000fd5b5050505050565b61017c81610077565b306001600160a01b0316632e716fb16040518163ffffffff1660e01b8152600401602060405180830381865afa1580156101ba573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906101de9190610254565b6001600160a01b0316631913592a6040518163ffffffff1660e01b8152600401600060405180830381600087803b15801561015857600080fd5b6001600160a01b038116811461022d57600080fd5b50565b60006020828403121561024257600080fd5b813561024d81610218565b9392505050565b60006020828403121561026657600080fd5b815161024d8161021856fea26469706673582212200d71f9cd831b3c67d6f6131f807ee7fc47d21f07fe8f7b90a01dab56abb8403464736f6c63430008170033";
        address incrementerAddress = address(0x5cB7957c702bB6BB8F22aCcf66657F0defd4550b);

        bytes[] memory scriptSources = new bytes[](1);
        scriptSources[0] = incrementer;
        bytes32 nextNonce = bytes32(uint256(0));
        bytes memory scriptCalldata = abi.encodeWithSignature("incrementCounter(address)", counter);

        assertEq(scriptCalldata, hex"e5910ae7000000000000000000000000f62849f9a0b5bf2913b396098f7c7019b51a820a");
        assertEq(block.chainid, 31337);

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            nonce: nextNonce,
            isReplayable: true,
            scriptAddress: incrementerAddress,
            scriptSources: scriptSources,
            scriptCalldata: scriptCalldata,
            expiry: 9999999999999
        });

        /*
        ethers.TypedDataEncoder.encode(
           {
               name: 'Quark Wallet',
               version: '1',
               chainId: 31337,
               verifyingContract: '0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9'
           },
           { QuarkOperation: [
               { name: 'nonce', type: 'bytes32' },
               { name: 'isReplayable', type: 'bool' },
               { name: 'scriptAddress', type: 'address' },
               { name: 'scriptSources', type: 'bytes[]' },
               { name: 'scriptCalldata', type: 'bytes' },
               { name: 'expiry', type: 'uint256' }
           ]},
           {
                nonce: '0x0000000000000000000000000000000000000000000000000000000000000000',
                isReplayable: true,
                scriptAddress: '0x5cB7957c702bB6BB8F22aCcf66657F0defd4550b',
                scriptSources: ['0x608060405234801561001057600080fd5b506102a7806100206000396000f3fe608060405234801561001057600080fd5b50600436106100365760003560e01c80636b582b7614610056578063e5910ae714610069575b73f62849f9a0b5bf2913b396098f7c7019b51a820a61005481610077565b005b610054610064366004610230565b610173565b610054610077366004610230565b806001600160a01b031663d09de08a6040518163ffffffff1660e01b8152600401600060405180830381600087803b1580156100b257600080fd5b505af11580156100c6573d6000803e3d6000fd5b50505050806001600160a01b031663d09de08a6040518163ffffffff1660e01b8152600401600060405180830381600087803b15801561010557600080fd5b505af1158015610119573d6000803e3d6000fd5b50505050806001600160a01b031663d09de08a6040518163ffffffff1660e01b8152600401600060405180830381600087803b15801561015857600080fd5b505af115801561016c573d6000803e3d6000fd5b5050505050565b61017c81610077565b306001600160a01b0316632e716fb16040518163ffffffff1660e01b8152600401602060405180830381865afa1580156101ba573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906101de9190610254565b6001600160a01b0316631913592a6040518163ffffffff1660e01b8152600401600060405180830381600087803b15801561015857600080fd5b6001600160a01b038116811461022d57600080fd5b50565b60006020828403121561024257600080fd5b813561024d81610218565b9392505050565b60006020828403121561026657600080fd5b815161024d8161021856fea26469706673582212200d71f9cd831b3c67d6f6131f807ee7fc47d21f07fe8f7b90a01dab56abb8403464736f6c63430008170033'],
                scriptCalldata: '0xe5910ae7000000000000000000000000f62849f9a0b5bf2913b396098f7c7019b51a820a',
                expiry: 9999999999999
           }
        )

        0x1901
        ce5fced5138ae147492ff6ba56247e9d6f30bbbe45ae60eb0a0135d528a94be4
        115a39f16a8c9e3e390e94dc858a17eba53b5358382af38b02f1ac31c2b5f9b0
        */

        bytes32 domainHash = new SignatureHelper().domainSeparator(wallet_);
        assertEq(domainHash, hex"ce5fced5138ae147492ff6ba56247e9d6f30bbbe45ae60eb0a0135d528a94be4");

        bytes32 structHash = new SignatureHelper().opStructHash(op);
        assertEq(structHash, hex"115a39f16a8c9e3e390e94dc858a17eba53b5358382af38b02f1ac31c2b5f9b0");
    }

    function testRevertsForBadCalldata() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        assertEq(counter.number(), 0);

        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(wallet);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // submitter calls executeQuarkOperation with the signed op, but they manipulate the calldata
        op.scriptCalldata = abi.encodeWithSignature("decrementCounter(address)", counter);
        vm.expectRevert(QuarkWallet.BadSignatory.selector);

        // gas: meter execute
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);

        // counter is unchanged
        assertEq(counter.number(), 0);

        // nonce is not spent
        assertEq(nonceManager.submissions(address(wallet), op.nonce), bytes32(uint256(0)));
    }

    function testRevertsForBadExpiry() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        assertEq(counter.number(), 0);

        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(wallet);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // submitter calls executeQuarkOperation with the signed op, but they manipulate the expiry
        op.expiry += 1;
        vm.expectRevert(QuarkWallet.BadSignatory.selector);

        // gas: meter execute
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);

        // counter is unchanged
        assertEq(counter.number(), 0);

        // alice's nonce is not set
        assertEq(nonceManager.submissions(address(wallet), op.nonce), bytes32(uint256(0)));
    }

    function testRevertsOnReusedNonce() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        assertEq(counter.number(), 0);

        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(wallet);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // gas: meter execute
        vm.resumeGasMetering();

        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(counter.number(), 3);
        assertEq(nonceManager.submissions(address(wallet), op.nonce), bytes32(type(uint256).max));

        // submitter tries to reuse the same signature twice, for a non-replayable operation
        vm.expectRevert(
            abi.encodeWithSelector(QuarkNonceManager.NonReplayableNonce.selector, address(wallet), op.nonce, op.nonce)
        );
        wallet.executeQuarkOperation(op, v, r, s);
    }

    function testRevertsForExpiredSignature() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        assertEq(counter.number(), 0);

        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(wallet);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // the expiry block arrives
        vm.warp(op.expiry);

        // submitter calls executeQuarkOperation with an expired signature
        vm.expectRevert(QuarkWallet.SignatureExpired.selector);

        // gas: meter execute
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(counter.number(), 0);
        assertEq(nonceManager.submissions(address(wallet), op.nonce), bytes32(uint256(0)));
    }

    function testRevertsInvalidS() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        assertEq(counter.number(), 0);

        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(wallet);
        (uint8 v, bytes32 r, /* bytes32 s */ ) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // 1 greater than the max value of s
        bytes32 invalidS = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A1;

        // submitter calls executeQuarkOperation with invalid `s` value
        vm.expectRevert(QuarkWallet.InvalidSignature.selector);

        // gas: meter execute
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, invalidS);

        assertEq(counter.number(), 0);
        assertEq(nonceManager.submissions(address(wallet), op.nonce), bytes32(uint256(0)));
    }

    // TODO: Uncomment when replay tokens are supported
    // function testNonceIsNotSetForReplayableOperation() public {
    //     // gas: do not meter set-up
    //     vm.pauseGasMetering();
    //     bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");

    //     assertEq(counter.number(), 0);

    //     QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
    //         wallet,
    //         incrementer,
    //         abi.encodeWithSignature("incrementCounterReplayable(address)", counter),
    //         ScriptType.ScriptSource
    //     );

    //     (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

    //     // submitter calls executeQuarkOperation with the signed operation
    //     // gas: meter execute
    //     vm.resumeGasMetering();
    //     wallet.executeQuarkOperation(op, v, r, s);

    //     // counter is incremented
    //     assertEq(counter.number(), 3);

    //     // nonce is NOT spent; the operation is replayable
    //     assertEq(nonceManager.isNonceSet(address(wallet), op.nonce), false);

    //     // submitter executes the operation a second time
    //     wallet.executeQuarkOperation(op, v, r, s);

    //     // counter is incremented
    //     assertEq(counter.number(), 6);

    //     // nonce is still not spent
    //     assertEq(nonceManager.isNonceSet(address(wallet), op.nonce), false);
    // }

    function testRevertBadRequirements() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");
        bytes memory executeWithRequirements =
            new YulHelper().getCode("ExecuteWithRequirements.sol/ExecuteWithRequirements.json");

        address incrementerAddress = codeJar.saveCode(incrementer);

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            executeWithRequirements,
            abi.encodeCall(
                ExecuteWithRequirements.runWithRequirements,
                (new bytes32[](0), incrementerAddress, abi.encodeWithSignature("incrementCounter(address)", counter))
            ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);

        // submitter alters the requirements
        bytes32[] memory badRequirements = new bytes32[](1);
        badRequirements[0] = bytes32(uint256(123));
        op.scriptCalldata = abi.encodeCall(
            ExecuteWithRequirements.runWithRequirements,
            (badRequirements, incrementerAddress, abi.encodeWithSignature("incrementCounter(address)", counter))
        );

        // submitter cannot execute the operation because the signature will not match
        vm.expectRevert(QuarkWallet.BadSignatory.selector);

        // gas: meter execute
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(counter.number(), 0);
        assertEq(nonceManager.submissions(address(wallet), op.nonce), bytes32(uint256(0)));
    }

    function testRequirements() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();
        bytes memory incrementer = new YulHelper().getCode("Incrementer.sol/Incrementer.json");
        bytes memory executeWithRequirements =
            new YulHelper().getCode("ExecuteWithRequirements.sol/ExecuteWithRequirements.json");

        address incrementerAddress = codeJar.saveCode(incrementer);

        QuarkWallet.QuarkOperation memory firstOp = incrementCounterOperation(wallet);
        (uint8 v1, bytes32 r1, bytes32 s1) = new SignatureHelper().signOp(alicePrivateKey, wallet, firstOp);

        bytes32[] memory requirements = new bytes32[](1);
        requirements[0] = firstOp.nonce;
        QuarkWallet.QuarkOperation memory dependentOp = new QuarkOperationHelper().newBasicOpWithCalldata(
            wallet,
            executeWithRequirements,
            abi.encodeCall(
                ExecuteWithRequirements.runWithRequirements,
                (requirements, incrementerAddress, abi.encodeWithSignature("incrementCounter(address)", counter))
            ),
            ScriptType.ScriptSource
        );

        dependentOp.nonce = new QuarkOperationHelper().incrementNonce(firstOp.nonce);

        (uint8 v2, bytes32 r2, bytes32 s2) = new SignatureHelper().signOp(alicePrivateKey, wallet, dependentOp);

        // attempting to execute the second operation first reverts
        vm.expectRevert(abi.encodeWithSelector(ExecuteWithRequirements.RequirementNotMet.selector, firstOp.nonce));

        // gas: meter execute
        vm.resumeGasMetering();
        wallet.executeQuarkOperation(dependentOp, v2, r2, s2);

        // but once the first operation is executed...
        wallet.executeQuarkOperation(firstOp, v1, r1, s1);
        assertEq(counter.number(), 3);
        // the second can be executed
        wallet.executeQuarkOperation(dependentOp, v2, r2, s2);
        // and its effect can be observed
        assertEq(counter.number(), 6);
    }
}
