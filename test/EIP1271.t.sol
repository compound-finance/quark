pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/console.sol";

import {QuarkWallet} from "../src/QuarkWallet.sol";
import {CodeJar} from "../src/CodeJar.sol";
import {Counter} from "./lib/Counter.sol";
import {YulHelper} from "./lib/YulHelper.sol";
import {SignatureHelper} from "./lib/SignatureHelper.sol";
import {EIP1271Signer} from "./lib/EIP1271Signer.sol";

contract EIP1271Test is Test {
    CodeJar public codeJar;
    Counter public counter;
    QuarkWallet public aliceWallet;

    uint256 alicePrivateKey = 0xa11ce;
    address alice; // see setup()

    function setUp() public {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));

        alice = vm.addr(alicePrivateKey);
        aliceWallet = new QuarkWallet(alice, codeJar);
    }

    function incrementCounterOperation(uint256 nonce)
        public
        returns (QuarkWallet.QuarkOperation memory)
    {
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");
        // XXX delete
        uint256[] memory requirements;
        return QuarkWallet.QuarkOperation({
            scriptSource: incrementer,
            scriptCalldata: abi.encodeWithSignature("incrementCounter(address)", counter),
            nonce: nonce,
            expiry: block.timestamp + 1000,
            allowCallback: false,
            isReplayable: false,
            requirements: requirements
        });
    }

    function testReturnsMagicValueForValidSignature() public {
        // QuarkWallet is owned by a smart contract that always approves signatures
        EIP1271Signer signatureApprover = new EIP1271Signer(true);
        QuarkWallet contractWallet = new QuarkWallet(address(signatureApprover), codeJar);

        // signature from alice; doesn't matter because the EIP1271Signer will approve anything
        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(1);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);
        contractWallet.executeQuarkOperation(op, v, r, s);

        // counter has incremented
        assertEq(counter.number(), 3);
    }

    function testRevertsIfSignerContractReturnsFalse() public {
        // QuarkWallet is owned by a smart contract that always rejects signatures
        EIP1271Signer signatureApprover = new EIP1271Signer(false);
        QuarkWallet contractWallet = new QuarkWallet(address(signatureApprover), codeJar);

        // signature from alice; doesn't matter because the EIP1271Signer will reject anything
        QuarkWallet.QuarkOperation memory op = incrementCounterOperation(1);
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        vm.expectRevert(QuarkWallet.InvalidSignature.selector);
        contractWallet.executeQuarkOperation(op, v, r, s);

        // counter has not incremented
        assertEq(counter.number(), 0);
    }
}
