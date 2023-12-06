pragma solidity 0.8.19;

import "forge-std/console.sol";

import {Test} from "forge-std/Test.sol";
import {QuarkWallet} from "../src/QuarkWallet.sol";
import {CodeJar} from "../src/CodeJar.sol";
import {Counter} from "./lib/Counter.sol";
import {YulHelper} from "./lib/YulHelper.sol";
import {QuarkStateManager} from "../src/QuarkStateManager.sol";
import {SignatureHelper} from "./lib/SignatureHelper.sol";
import {QuarkOperationHelper, ScriptType} from "./lib/QuarkOperationHelper.sol";

contract ExecutorTest is Test {
    CodeJar public codeJar;
    Counter public counter;
    QuarkStateManager public stateManager;

    uint256 alicePrivateKey = 0xa11ce;
    address aliceAccount = vm.addr(alicePrivateKey);
    QuarkWallet public aliceWallet;

    uint256 bobPrivateKey = 0xb0b1337;
    address bobAccount = vm.addr(bobPrivateKey);
    QuarkWallet public bobWallet;

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        stateManager = new QuarkStateManager();
        console.log("QuarkStateManager deployed to: %s", address(stateManager));

        counter = new Counter();
        console.log("Counter deployed to: %s", address(counter));

        // alice sets her EOA to be her wallet's executor
        aliceWallet = new QuarkWallet(aliceAccount, aliceAccount, codeJar, stateManager);
        console.log("aliceWallet at: %s", address(aliceWallet));

        // bob sets alice's wallet as his wallet's executor
        bobWallet = new QuarkWallet(bobAccount, address(aliceWallet), codeJar, stateManager);
        console.log("bobWallet at: %s", address(bobWallet));
    }

    function testExecutorCanDirectCall() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();

        bytes memory ethcall = new YulHelper().getDeployed("Ethcall.sol/Ethcall.json");
        address ethcallAddress = codeJar.saveCode(ethcall);

        bytes memory executeOnBehalf = new YulHelper().getDeployed("ExecuteOnBehalf.sol/ExecuteOnBehalf.json");
        address executeOnBehalfAddress = codeJar.saveCode(executeOnBehalf);

        vm.startPrank(aliceAccount);

        // gas: meter execute
        vm.resumeGasMetering();

        // execute counter.increment(5) as bob from alice's wallet (that is, from bob's wallet's executor)
        aliceWallet.executeScript(
            stateManager.nextNonce(address(aliceWallet)),
            executeOnBehalfAddress,
            abi.encodeWithSignature(
                "run(address,uint96,address,bytes)",
                address(bobWallet),
                stateManager.nextNonce(address(bobWallet)),
                address(ethcallAddress),
                abi.encodeWithSignature(
                    "run(address,bytes,uint256)", address(counter), abi.encodeWithSignature("increment(uint256)", 5), 0
                )
            )
        );

        assertEq(counter.number(), 5);
    }

    function testExecutorCanDirectCallBySig() public {
        // gas: do not meter set-up
        vm.pauseGasMetering();

        bytes memory ethcall = new YulHelper().getDeployed("Ethcall.sol/Ethcall.json");
        address ethcallAddress = codeJar.saveCode(ethcall);

        bytes memory executeOnBehalf = new YulHelper().getDeployed("ExecuteOnBehalf.sol/ExecuteOnBehalf.json");

        QuarkWallet.QuarkOperation memory op = new QuarkOperationHelper().newBasicOpWithCalldata(
            aliceWallet,
            executeOnBehalf,
            abi.encodeWithSignature(
                "run(address,uint96,address,bytes)",
                address(bobWallet),
                stateManager.nextNonce(address(bobWallet)),
                address(ethcallAddress),
                abi.encodeWithSignature(
                    "run(address,bytes,uint256)", address(counter), abi.encodeWithSignature("increment(uint256)", 3), 0
                )
            ),
            ScriptType.ScriptSource
        );
        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, aliceWallet, op);

        // gas: meter execute
        vm.resumeGasMetering();
        aliceWallet.executeQuarkOperation(op, v, r, s);
        assertEq(counter.number(), 3);
    }
}
