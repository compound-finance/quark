// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./lib/YulHelper.sol";
import "./lib/Counter.sol";
import "./lib/CounterScript.sol";
import "./lib/MaxCounterScript.sol";
import "./lib/Invariant.sol";

import "../src/CodeJar.sol";
import "../src/Relayer.sol";
import "../src/RelayerAtomic.sol";

contract CodeJarTest is Test {
    event Ping(uint256 value);

    CodeJar public codeJar;

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));
    }

    function setUp() public {
        // nothing
    }

    function testCodeJarFirstDeploy() public {
        uint256 gasLeft = gasleft();
        address scriptAddress = codeJar.saveCode(hex"11223344");
        uint256 gasUsed = gasLeft - gasleft();
        assertEq(scriptAddress.code, hex"11223344");
        assertApproxEqAbs(gasUsed, 42000, 3000);
    }

    function testCodeJarSecondDeploy() public {
        address scriptAddress = codeJar.saveCode(hex"11223344");

        uint256 gasLeft = gasleft();
        address scriptAddressNext = codeJar.saveCode(hex"11223344");        
        uint256 gasUsed = gasLeft - gasleft();
        assertEq(scriptAddress, scriptAddressNext);
        assertEq(scriptAddressNext.code, hex"11223344");

        assertApproxEqAbs(gasUsed, 3000, 1000);
    }

    function testCodeJarInputVariety() public {
        bytes[] memory scripts = new bytes[](8);
        scripts[0] = hex"";
        scripts[1] = hex"00";
        scripts[2] = hex"11";
        scripts[3] = hex"112233";
        scripts[4] = hex"00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff";
        scripts[5] = hex"00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff11";
        scripts[6] = hex"00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff";
        scripts[7] = hex"00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff11";

        for (uint8 i = 0; i < scripts.length; i++) {
            assertEq(codeJar.saveCode(scripts[i]).code, scripts[i]);
        }
    }

    function testCodeJarCounter() public {
        address scriptAddress = codeJar.saveCode(type(Counter).runtimeCode);
        assertEq(scriptAddress.code, type(Counter).runtimeCode);

        Counter counter = Counter(scriptAddress);
        assertEq(counter.number(), 0);
        counter.increment();
        assertEq(counter.number(), 1);
    }

    function testCodeJarSelfDestruct() public {
        // TODO: Consider how to handle this since we run in a transaction and thus can't self destruct

        // PUSH0 [5F]; SELFDESTRUCT [FF]
        address scriptAddress = codeJar.saveCode(hex"5fff");
        assertEq(scriptAddress.code, hex"5fff");
        scriptAddress.call(hex"");
        assertEq(scriptAddress.code, hex"");
        codeJar.saveCode(hex"5fff");
        assertEq(scriptAddress.code, hex"5fff");
    }

    // TODO: Test code too large (overflow)
}
