pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/console.sol";

import { Test } from "forge-std/Test.sol";
import { QuarkWallet } from "../src/QuarkWallet.sol";
import { CodeJar} from "../src/CodeJar.sol";
import { Counter } from "./lib/Counter.sol";
import { YulHelper } from "./lib/YulHelper.sol";

contract CallbacksTest is Test {

    CodeJar public codeJar;
    Counter public counter;

    uint256 alicePrivateKey = 0x9810473;
    address aliceAccount; // see constructor()
    QuarkWallet public aliceWallet;

    bytes32 internal constant QUARK_OPERATION_TYPEHASH = keccak256("QuarkOperation(bytes scriptSource,bytes scriptCalldata,uint256 nonce,uint256 expiry,bool allowCallback)");

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
        vm.prank(address(0xbeef));
        aliceWallet.executeQuarkOperation(op, v, r, s);

        assertEq(counter.number(), 11);
    }
}