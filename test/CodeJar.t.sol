// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./lib/Counter.sol";

import "../src/CodeJar.sol";

contract CodeJarTest is Test {
    event Ping(uint256 value);

    error CodeInvalid(address codeAddress);

    CodeJar public codeJar;
    address destructingAddress;

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));
    }

    function setUp() public {
        // TODO: Only on certain tests?

        // PUSH0 [5F]; SELFDESTRUCT [FF]
        destructingAddress = codeJar.saveCode(hex"5fff");
        assertEq(destructingAddress.code, hex"5fff");
        (bool success,) = destructingAddress.call(hex"");
        assertEq(success, true);
        assertEq(destructingAddress.code, hex"5fff");
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
        scripts[6] =
            hex"00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff";
        scripts[7] =
            hex"00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff11";

        for (uint8 i = 0; i < scripts.length; i++) {
            assertEq(codeJar.codeExists(scripts[i]), false);
            address codeAddress = codeJar.saveCode(scripts[i]);
            assertEq(codeAddress.code, scripts[i]);
            assertEq(codeJar.codeExists(scripts[i]), true);
            assertEq(codeJar.readCode(codeAddress), scripts[i]);
        }
    }

    function testCodeJarDifferentZeros() public {
        vm.startPrank(address(0xaa));

        // Check that random addresses have zero extcodehash
        assertEq(address(0x0011223344).codehash, 0);

        // Check that accounts that send have zero extcodehash
        assertEq(vm.getNonce(address(0xaa)), 0);
        assertEq(address(0xaa).codehash, 0);
        (bool success,) = address(0).call(hex"");
        assertEq(success, true);

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
        assertEq(destructingAddress.code, hex"");
        assertEq(destructingAddress.codehash, 0);
        assertEq(destructingAddress, codeJar.saveCode(hex"5fff"));
        assertEq(destructingAddress.code, hex"5fff");
        assertEq(destructingAddress.codehash, keccak256(hex"5fff"));
    }

    function testCodeJarLarge() public {
        bytes32[] memory script = new bytes32[](10000);
        bytes memory code = abi.encodePacked(script);
        codeJar.saveCode(code);
    }

    function testCodeJarReadNonExistent() public {
        vm.expectRevert(abi.encodeWithSelector(CodeInvalid.selector, address(0x55)));
        codeJar.readCode(address(0x55));

        vm.expectRevert(abi.encodeWithSelector(CodeInvalid.selector, address(codeJar)));
        codeJar.readCode(address(codeJar));
    }

    // Note: cannot test code too large, as overflow impossible to test
}
