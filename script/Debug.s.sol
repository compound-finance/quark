// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {Proxy} from "../src/Proxy.sol";
import {CodeJar} from "../src/CodeJar.sol";
import {QuarkWallet} from "../src/QuarkWallet.sol";
import {QuarkStateManager} from "../src/QuarkStateManager.sol";

contract Debug is Script {
    function run() public {
        address dummy = vm.addr(0x123abc);
        CodeJar codejar = new CodeJar();
        QuarkStateManager manager = new QuarkStateManager();

        console.log(dummy);

        QuarkWallet impl = new QuarkWallet(address(0), address(0), codejar, manager);
        Proxy proxy = new Proxy(address(impl), dummy, address(0), codejar, manager);
        (bool success, bytes memory result) = address(proxy).call(abi.encodeWithSignature("getSigner()"));
        if (!success) {
            assembly { revert(add(result, 0x20), mload(result)) }
        }
        address signer = abi.decode(result, (address));
        console.log(signer);
    }
}
