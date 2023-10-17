pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/console.sol";

import {Test} from "forge-std/Test.sol";
import {QuarkWallet} from "../src/QuarkWallet.sol";
import {CodeJar} from "../src/CodeJar.sol";
import {Counter} from "./lib/Counter.sol";
import {YulHelper} from "./lib/YulHelper.sol";

contract CallbacksTest is Test {
    CodeJar public codeJar;
    Counter public counter;

    uint256 alicePrivateKey = 0x9810473;
    address aliceAccount; // see constructor()
    QuarkWallet public aliceWallet;

    bytes32 internal constant QUARK_OPERATION_TYPEHASH = keccak256("QuarkOperation(bytes scriptSource,bytes scriptCalldata,uint256 nonce,uint256 expiry,bool allowCallback,bool isReplayable,uint256[] requirements)");

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));

        aliceAccount = vm.addr(alicePrivateKey);
        aliceWallet = new QuarkWallet(aliceAccount, codeJar);
    }

    function signOp(uint256 privateKey, QuarkWallet wallet, QuarkWallet.QuarkOperation memory op) internal view returns (uint8, bytes32, bytes32) {
        bytes32 structHash = keccak256(abi.encode(
            QUARK_OPERATION_TYPEHASH,
            op.scriptSource,
            op.scriptCalldata,
            op.nonce,
            op.expiry,
            op.allowCallback,
            op.isReplayable,
            op.requirements
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

        bytes memory callbackFromCounter =
            new YulHelper().getDeployed("CallbackFromCounter.sol/CallbackFromCounter.json");

        uint256 nonce = aliceWallet.nextUnusedNonce();

        uint256[] memory requirements;
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: callbackFromCounter,
            scriptCalldata: abi.encodeWithSignature("doIncrementAndCallback(address)", counter),
            nonce: nonce,
            expiry: block.timestamp + 1000,
            allowCallback: true,
            isReplayable: false,
            requirements: requirements
        });
        (uint8 v, bytes32 r, bytes32 s) = signOp(alicePrivateKey, aliceWallet, op);
        aliceWallet.executeQuarkOperation(op, v, r, s);

        assertEq(counter.number(), 11);
    }

    function testRevertsNestedCallbackScriptIfCallbackAlreadyActive() public {
        bytes memory callbackFromCounter =
            new YulHelper().getDeployed("CallbackFromCounter.sol/CallbackFromCounter.json");
        bytes memory executeOtherScript =
            new YulHelper().getDeployed("ExecuteOtherOperation.sol/ExecuteOtherOperation.json");

        uint256 nonce1 = aliceWallet.nextUnusedNonce();
        uint256[] memory requirements;
        QuarkWallet.QuarkOperation memory nestedOp = QuarkWallet.QuarkOperation({
            scriptSource: callbackFromCounter,
            scriptCalldata: abi.encodeWithSignature("doIncrementAndCallback(address)", counter),
            nonce: nonce1,
            expiry: block.timestamp + 1000,
            allowCallback: true,
            isReplayable: false,
            requirements: requirements
        });
        (uint8 v_, bytes32 r_, bytes32 s_) = signOp(alicePrivateKey, aliceWallet, nestedOp);

        uint256 nonce2 = nonce1 + 1;
        QuarkWallet.QuarkOperation memory parentOp = QuarkWallet.QuarkOperation({
            scriptSource: executeOtherScript,
            scriptCalldata: abi.encodeWithSignature(
                "run((bytes,bytes,uint256,uint256,bool,bool,uint256[]),uint8,bytes32,bytes32)",
                nestedOp,
                v_,
                r_,
                s_
            ),
            nonce: nonce2,
            expiry: block.timestamp + 1000,
            allowCallback: true,
            isReplayable: false,
            requirements: requirements
        });
        (uint8 v, bytes32 r, bytes32 s) = signOp(alicePrivateKey, aliceWallet, parentOp);

        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector,
                abi.encodeWithSelector(QuarkWallet.QuarkCallbackAlreadyActive.selector)
            )
        );
        aliceWallet.executeQuarkOperation(parentOp, v, r, s);
    }

    function testNestedCallWithNoCallbackSucceeds() public {
        assertEq(counter.number(), 0);

        bytes memory counterScript = new YulHelper().getDeployed("CounterScript.sol/CounterScript.json");
        bytes memory executeOtherScript =
            new YulHelper().getDeployed("ExecuteOtherOperation.sol/ExecuteOtherOperation.json");

        uint256 nonce1 = aliceWallet.nextUnusedNonce();
        uint256[] memory requirements;
        QuarkWallet.QuarkOperation memory nestedOp = QuarkWallet.QuarkOperation({
            scriptSource: counterScript,
            scriptCalldata: abi.encodeWithSignature("run(address)", counter),
            nonce: nonce1,
            expiry: block.timestamp + 1000,
            allowCallback: false,
            isReplayable: false,
            requirements: requirements
        });
        (uint8 v_, bytes32 r_, bytes32 s_) = signOp(alicePrivateKey, aliceWallet, nestedOp);

        uint256 nonce2 = nonce1 + 1;
        QuarkWallet.QuarkOperation memory parentOp = QuarkWallet.QuarkOperation({
            scriptSource: executeOtherScript,
            scriptCalldata: abi.encodeWithSignature(
                "run((bytes,bytes,uint256,uint256,bool,bool,uint256[]),uint8,bytes32,bytes32)",
                nestedOp,
                v_,
                r_,
                s_
            ),
            nonce: nonce2,
            expiry: block.timestamp + 1000,
            allowCallback: true,
            isReplayable: false,
            requirements: requirements
        });
        (uint8 v, bytes32 r, bytes32 s) = signOp(alicePrivateKey, aliceWallet, parentOp);

        aliceWallet.executeQuarkOperation(parentOp, v, r, s);
        assertEq(counter.number(), 2);
    }

    function testAllowCallbackDoesNotRequireGettingCalledBack() public {
        assertEq(counter.number(), 0);
        bytes memory counterScript = new YulHelper().getDeployed("CounterScript.sol/CounterScript.json");
        uint256 nonce = aliceWallet.nextUnusedNonce();
        uint256[] memory requirements;
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: counterScript,
            scriptCalldata: abi.encodeWithSignature("run(address)", counter),
            nonce: nonce,
            expiry: block.timestamp + 1000,
            allowCallback: true,
            isReplayable: false,
            requirements: requirements
        });
        (uint8 v, bytes32 r, bytes32 s) = signOp(alicePrivateKey, aliceWallet, op);

        aliceWallet.executeQuarkOperation(op, v, r, s);
        assertEq(counter.number(), 2);
    }

    function testRevertsOnCallbackWhenNoActiveCallback() public {
        bytes memory callbackFromCounter =
            new YulHelper().getDeployed("CallbackFromCounter.sol/CallbackFromCounter.json");

        uint256 nonce = aliceWallet.nextUnusedNonce();
        uint256[] memory requirements;
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: callbackFromCounter,
            scriptCalldata: abi.encodeWithSignature("doIncrementAndCallback(address)", counter),
            nonce: nonce,
            expiry: block.timestamp + 1000,
            allowCallback: false,
            isReplayable: false,
            requirements: requirements
        });
        (uint8 v, bytes32 r, bytes32 s) = signOp(alicePrivateKey, aliceWallet, op);

        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector, abi.encodeWithSelector(QuarkWallet.NoActiveCallback.selector)
            )
        );
        aliceWallet.executeQuarkOperation(op, v, r, s);
    }
}
