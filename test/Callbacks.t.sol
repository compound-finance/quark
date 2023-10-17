pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/console.sol";

import { Test } from "forge-std/Test.sol";
import { QuarkWallet } from "../src/QuarkWallet.sol";
import { CodeJar} from "../src/CodeJar.sol";
import { Counter } from "./lib/Counter.sol";
import { YulHelper } from "./lib/YulHelper.sol";
import { SponsorTransaction } from "./lib/SponsorTransaction.sol";

contract CallbacksTest is Test {

    CodeJar public codeJar;
    Counter public counter;

    uint256 alicePrivateKey = 0x9810473;
    address payable aliceAccount; // see constructor()
    QuarkWallet public aliceWallet;

    uint256 bobPrivateKey = 0x1237789;
    address payable bobAccount; // see constructor()
    QuarkWallet public bobWallet;

    bytes32 internal constant QUARK_OPERATION_TYPEHASH = keccak256("QuarkOperation(bytes scriptSource,bytes scriptCalldata,uint256 nonce,uint256 expiry,bool allowCallback)");

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));

        aliceAccount = payable(vm.addr(alicePrivateKey));
        aliceWallet = new QuarkWallet(aliceAccount, codeJar);
        console.log("alice account, wallet");
        console.logAddress(aliceAccount);
        console.logAddress(address(aliceWallet));

        bobAccount = payable(vm.addr(bobPrivateKey));
        bobWallet = new QuarkWallet(bobAccount, codeJar);
        console.log("bob account, wallet");
        console.logAddress(bobAccount);
        console.logAddress(address(bobWallet));
    }

    function signOp(uint256 privateKey, QuarkWallet wallet, QuarkWallet.QuarkOperation memory op) internal view returns (uint8, bytes32, bytes32) {
        bytes32 structHash = keccak256(abi.encode(
            QUARK_OPERATION_TYPEHASH,
            op.scriptSource,
            op.scriptCalldata,
            op.nonce,
            op.expiry,
            op.allowCallback
        ));
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            wallet.DOMAIN_SEPARATOR(),
            structHash
        ));
        return vm.sign(privateKey, digest);
    }

    function testCallbackFromCounter() public {
        assertEq(counter.number(), 0);

        bytes memory callbackFromCounter = new YulHelper().getDeployed("CallbackFromCounter.sol/CallbackFromCounter.json");

        uint256 nonce = aliceWallet.nextUnusedNonce();

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: callbackFromCounter,
            scriptCalldata: abi.encodeWithSignature(
                "doIncrementAndCallback(address)",
                counter
            ),
            nonce: nonce,
            expiry: block.timestamp + 1000,
            allowCallback: true
        });
        (uint8 v, bytes32 r, bytes32 s) = signOp(alicePrivateKey, aliceWallet, op);
        aliceWallet.executeQuarkOperation(op, v, r, s);

        assertEq(counter.number(), 11);
    }

    function testRevertsNestedCallbackScriptIfCallbackAlreadyActive() public {
        bytes memory callbackFromCounter = new YulHelper().getDeployed("CallbackFromCounter.sol/CallbackFromCounter.json");
        bytes memory executeOtherScript = new YulHelper().getDeployed("ExecuteOtherOperation.sol/ExecuteOtherOperation.json");

        uint256 nonce1 = aliceWallet.nextUnusedNonce();
        QuarkWallet.QuarkOperation memory nestedOp = QuarkWallet.QuarkOperation({
            scriptSource: callbackFromCounter,
            scriptCalldata: abi.encodeWithSignature(
                "doIncrementAndCallback(address)",
                counter
            ),
            nonce: nonce1,
            expiry: block.timestamp + 1000,
            allowCallback: true
        });
        (uint8 v_, bytes32 r_, bytes32 s_) = signOp(alicePrivateKey, aliceWallet, nestedOp);

        uint256 nonce2 = nonce1 + 1;
        QuarkWallet.QuarkOperation memory parentOp = QuarkWallet.QuarkOperation({
            scriptSource: executeOtherScript,
            scriptCalldata: abi.encodeWithSignature(
                "run((bytes,bytes,uint256,uint256,bool),uint8,bytes32,bytes32)",
                nestedOp,
                v_,
                r_,
                s_
            ),
            nonce: nonce2,
            expiry: block.timestamp + 1000,
            allowCallback: true
        });
        (uint8 v, bytes32 r, bytes32 s) = signOp(alicePrivateKey, aliceWallet, parentOp);

        vm.expectRevert(
            abi.encodeWithSelector(QuarkWallet.QuarkCallError.selector,
                abi.encodeWithSelector(QuarkWallet.QuarkCallbackAlreadyActive.selector))
        );
        aliceWallet.executeQuarkOperation(parentOp, v, r, s);
    }

    function testNestedCallWithNoCallbackSucceeds() public {
        assertEq(counter.number(), 0);

        bytes memory counterScript = new YulHelper().getDeployed("CounterScript.sol/CounterScript.json");
        bytes memory executeOtherScript = new YulHelper().getDeployed("ExecuteOtherOperation.sol/ExecuteOtherOperation.json");

        uint256 nonce1 = aliceWallet.nextUnusedNonce();
        QuarkWallet.QuarkOperation memory nestedOp = QuarkWallet.QuarkOperation({
            scriptSource: counterScript,
            scriptCalldata: abi.encodeWithSignature(
                "run(address)",
                counter
            ),
            nonce: nonce1,
            expiry: block.timestamp + 1000,
            allowCallback: false
        });
        (uint8 v_, bytes32 r_, bytes32 s_) = signOp(alicePrivateKey, aliceWallet, nestedOp);

        uint256 nonce2 = nonce1 + 1;
        QuarkWallet.QuarkOperation memory parentOp = QuarkWallet.QuarkOperation({
            scriptSource: executeOtherScript,
            scriptCalldata: abi.encodeWithSignature(
                "run((bytes,bytes,uint256,uint256,bool),uint8,bytes32,bytes32)",
                nestedOp,
                v_,
                r_,
                s_
            ),
            nonce: nonce2,
            expiry: block.timestamp + 1000,
            allowCallback: true
        });
        (uint8 v, bytes32 r, bytes32 s) = signOp(alicePrivateKey, aliceWallet, parentOp);

        aliceWallet.executeQuarkOperation(parentOp, v, r, s);
        assertEq(counter.number(), 2);
    }

    function testAllowCallbackDoesNotRequireGettingCalledBack() public {
        assertEq(counter.number(), 0);
        bytes memory counterScript = new YulHelper().getDeployed("CounterScript.sol/CounterScript.json");
        uint256 nonce = aliceWallet.nextUnusedNonce();
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: counterScript,
            scriptCalldata: abi.encodeWithSignature(
                "run(address)",
                counter
            ),
            nonce: nonce,
            expiry: block.timestamp + 1000,
            allowCallback: true
        });
        (uint8 v, bytes32 r, bytes32 s) = signOp(alicePrivateKey, aliceWallet, op);

        aliceWallet.executeQuarkOperation(op, v, r, s);
        assertEq(counter.number(), 2);
    }

    function testRevertsOnCallbackWhenNoActiveCallback() public {
        bytes memory callbackFromCounter = new YulHelper().getDeployed("CallbackFromCounter.sol/CallbackFromCounter.json");

        uint256 nonce = aliceWallet.nextUnusedNonce();
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: callbackFromCounter,
            scriptCalldata: abi.encodeWithSignature(
                "doIncrementAndCallback(address)",
                counter
            ),
            nonce: nonce,
            expiry: block.timestamp + 1000,
            allowCallback: false
        });
        (uint8 v, bytes32 r, bytes32 s) = signOp(alicePrivateKey, aliceWallet, op);

        vm.expectRevert(
            abi.encodeWithSelector(QuarkWallet.QuarkCallError.selector,
                abi.encodeWithSelector(QuarkWallet.NoActiveCallback.selector))
        );
        aliceWallet.executeQuarkOperation(op, v, r, s);
    }

    function testSponsorTransactionScenario() public {
        bytes memory sponsorTransaction = new YulHelper().getDeployed("SponsorTransaction.sol/SponsorTransaction.json");
        bytes memory paySponsor = new YulHelper().getDeployed("PaySponsor.sol/PaySponsor.json");
        bytes memory callbackFromCounter = new YulHelper().getDeployed("CallbackFromCounter.sol/CallbackFromCounter.json");

        QuarkWallet.QuarkOperation memory bobUnderlyingOp = QuarkWallet.QuarkOperation({
            scriptSource: callbackFromCounter,
            scriptCalldata: abi.encodeWithSignature(
                "doIncrementAndCallback(address)",
                counter
            ),
            nonce: bobWallet.nextUnusedNonce(),
            expiry: block.timestamp + 1000,
            allowCallback: true
        });
        (uint8 bob_v, bytes32 bob_r, bytes32 bob_s) = signOp(bobPrivateKey, bobWallet, bobUnderlyingOp);

        QuarkWallet.QuarkOperation memory aliceOp = QuarkWallet.QuarkOperation({
            scriptSource: sponsorTransaction,
            scriptCalldata: abi.encodeWithSelector(
                SponsorTransaction.run.selector,
                100000000, // 1e8 feeAmount
                bobWallet,
                bobUnderlyingOp,
                bob_v,
                bob_r,
                bob_s
            ),
            nonce: aliceWallet.nextUnusedNonce(),
            expiry: block.timestamp + 1000,
            allowCallback: true
        });
        (uint8 alice_v, bytes32 alice_r, bytes32 alice_s) = signOp(alicePrivateKey, aliceWallet, aliceOp);

        vm.expectRevert(
            abi.encodeWithSelector(QuarkWallet.QuarkCallError.selector,
                abi.encodeWithSelector(SponsorTransaction.PaymentNotReceived.selector))
        );
        aliceWallet.executeQuarkOperation(aliceOp, alice_v, alice_r, alice_s);
    }

    /* NOTE: this is fairly contrived, since you're paying the sponsor in Eth anyway
     * It might make more sense if you were paying the sponsor to e.g.
     * submit a transaction for you at some point in the future when a
     * condition becomes true, or to pay with an ERC20 so you don't need
     * gas tokens. Should probably modify this to be more realistic.
     */
    function testSponsorTransactionSucceedsWithProperPayment() public {
        bytes memory sponsorTransaction = new YulHelper().getDeployed("SponsorTransaction.sol/SponsorTransaction.json");
        bytes memory paySponsor = new YulHelper().getDeployed("PaySponsor.sol/PaySponsor.json");
        bytes memory callbackFromCounter = new YulHelper().getDeployed("CallbackFromCounter.sol/CallbackFromCounter.json");

        vm.deal(address(bobWallet), 200000000); // 2e8

        QuarkWallet.QuarkOperation memory bobUnderlyingOp = QuarkWallet.QuarkOperation({
            scriptSource: callbackFromCounter,
            scriptCalldata: abi.encodeWithSignature(
                "doIncrementAndCallback(address)",
                counter
            ),
            nonce: bobWallet.nextUnusedNonce(),
            expiry: block.timestamp + 1000,
            allowCallback: true
        });

        QuarkWallet.QuarkOperation memory bobSponsoredOp = QuarkWallet.QuarkOperation({
            scriptSource: paySponsor,
            scriptCalldata: abi.encodeWithSignature(
                "runAndPay(address,bytes,uint256)",
                codeJar.saveCode(callbackFromCounter),
                abi.encodeWithSignature(
                    "doIncrementAndCallback(address)",
                    counter
                ),
                100000000 // amount to pay in wei
            ),
            nonce: bobWallet.nextUnusedNonce(),
            expiry: block.timestamp + 1000,
            allowCallback: true
        });
        (uint8 bob_v, bytes32 bob_r, bytes32 bob_s) = signOp(bobPrivateKey, bobWallet, bobSponsoredOp);

        QuarkWallet.QuarkOperation memory aliceOp2 = QuarkWallet.QuarkOperation({
            scriptSource: sponsorTransaction,
            scriptCalldata: abi.encodeWithSelector(
                SponsorTransaction.run.selector,
                100000000, // 1e8 feeAmount expected
                bobWallet,
                bobSponsoredOp,
                bob_v,
                bob_r,
                bob_s
            ),
            nonce: aliceWallet.nextUnusedNonce(),
            expiry: block.timestamp + 1000,
            allowCallback: true
        });
        (uint8 alice_v2, bytes32 alice_r2, bytes32 alice_s2) = signOp(alicePrivateKey, aliceWallet, aliceOp2);

        vm.prank(aliceAccount, aliceAccount);
        aliceWallet.executeQuarkOperation(aliceOp2, alice_v2, alice_r2, alice_s2);
        assertEq(address(aliceWallet).balance, 100000000);
        assertEq(address(bobWallet).balance, 100000000);
    }
}
