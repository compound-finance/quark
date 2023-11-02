pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/console.sol";

import {Test} from "forge-std/Test.sol";
import {QuarkWallet} from "../src/QuarkWallet.sol";
import {CodeJar} from "../src/CodeJar.sol";
import {Counter} from "./lib/Counter.sol";
import {YulHelper} from "./lib/YulHelper.sol";
import {QuarkStateManager} from "../src/QuarkStateManager.sol";
import {SignatureHelper} from "./lib/SignatureHelper.sol";
import {ExecuteWithRequirements} from "./lib/ExecuteWithRequirements.sol";

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

        aliceWallet = new QuarkWallet(aliceAccount, address(0), codeJar, stateManager);
        console.log("aliceWallet at: %s", address(aliceWallet));

        bobWallet = new QuarkWallet(bobAccount, address(aliceWallet), codeJar, stateManager);
        console.log("bobWallet at: %s", address(bobWallet));
    }

    function testExecutorCanDirectCall() public {
        bytes memory executeOnBehalf = new YulHelper().getDeployed("ExecuteOnBehalf.sol/ExecuteOnBehalf.json");

        vm.startPrank(aliceAccount);
        aliceWallet.executeQuarkOperation(
            aliceWallet.nextNonce(),
            codeJar.saveCode(executeOnBehalf),
            abi.encodeWithSignature(
                "run(address,uint256,address,bytes,bool)",
                address(bobWallet),
                bobWallet.nextNonce(),
                address(counter),
                abi.encodeWithSignature("increment(uint256)", (5)),
                false /* allowCallback */
            ),
            false /* allowCallback */
        );
    }
}
