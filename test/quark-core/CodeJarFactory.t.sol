// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "quark-core/src/CodeJarFactory.sol";

contract CodeJarFactoryTest is Test {
    function testCodeJarFactory() public {
        CodeJarFactory codeJarFactory = new CodeJarFactory();
        assertEq(address(codeJarFactory.codeJar()), address(0x3868F54Adb45ebb132dc7d2Ac3ff851EA66FeeD4));
    }
}
