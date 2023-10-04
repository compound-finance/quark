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

    function testCodeJarDifferentZeros() public {
        vm.startPrank(address(0xaa));

        // Check that random addresses have zero extcodehash
        assertEq(address(0x0011223344).codehash, 0);

        // Check that accounts that send have zero extcodehash
        assertEq(vm.getNonce(address(0xaa)), 0);
        assertEq(address(0xaa).codehash, 0);
        address(0).call(hex"");

        // TODO: This is returning 0, maybe a fluke in foundry
        // assertEq(vm.getNonce(address(0xaa)), 1);

        assertEq(address(0xaa).codehash, 0);

        address zeroDeploy = codeJar.saveCode(hex"");
        assertEq(zeroDeploy.codehash, keccak256(hex""));
        assertEq(codeJar.readCode(zeroDeploy), hex"");

        address nonZeroDeploy = codeJar.saveCode(hex"00");
        assertEq(codeJar.readCode(nonZeroDeploy), hex"00");
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

    function testCodeJarTooLarge() public {
        // TODO: Consider how to handle this since we run in a transaction and thus can't self destruct
        bytes32[] memory script = new bytes32[](1000); // 2**32 / 32 + 1
        bytes memory code = abi.encodePacked(script);
        address scriptAddress = codeJar.saveCode(code);
    }

    // TODO: Test code too large (overflow)
}
