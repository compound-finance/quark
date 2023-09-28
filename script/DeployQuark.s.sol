// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/QuarkWallet.sol";
import "../test/lib/YulHelper.sol";

contract CounterScript is Script {
    CodeJar public codeJar;

    function setUp() public {
        YulHelper yulHelper = new YulHelper();

        vm.allowCheatcodes(address(yulHelper));
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        codeJar.saveCode(
            yulHelper.getDeployed("LeverFlashLoan.sol/LeverFlashLoan.json")
        );

        vm.stopBroadcast();
    }

    function run() public {
        address alice = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        QuarkWallet wallet = new QuarkWallet{salt: 0}(alice, codeJar);

        console.log("Quark wallet deployed to:", address(wallet));

        vm.stopBroadcast();
    }
}
