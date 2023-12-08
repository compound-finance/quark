// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "test/lib/Counter.sol";

import "quark-core/src/CodeJar.sol";

contract CodeJarTest is Test {
    event Ping(uint256 value);

    CodeJar public codeJar;
    address destructingAddress;
    bytes destructingCode = hex"6000ff"; // PUSH1 [60]; 0 [00]; SELFDESTRUCT [FF]

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));
    }

    function setUp() public {
        // This setUp is only used for `testCodeJarSelfDestruct`. To test the state changes
        // from a selfdestruct in forge, the selfdestruct must be done in the setUp.
        // See: https://github.com/foundry-rs/foundry/issues/1543

        destructingAddress = codeJar.saveCode(destructingCode);
        assertEq(destructingAddress.code, destructingCode);
        (bool success,) = destructingAddress.call(hex"");
        assertEq(success, true);
        // Selfdestruct state changes do not take effect until after setUp
        assertEq(destructingAddress.code, destructingCode);
    }

    function testCodeJarSelfDestruct() public {
        assertEq(destructingAddress.code, hex"");
        assertEq(destructingAddress.codehash, 0);
        assertEq(destructingAddress, codeJar.saveCode(destructingCode));
        assertEq(destructingAddress.code, destructingCode);
        assertEq(destructingAddress.codehash, keccak256(destructingCode));
    }

    function testCodeJarFirstDeploy() public {
        uint256 gasLeft = gasleft();
        address scriptAddress = codeJar.saveCode(hex"11223344");
        uint256 gasUsed = gasLeft - gasleft();
        assertEq(scriptAddress.code, hex"11223344");
        assertApproxEqAbs(gasUsed, 42000, 3000);
    }

    function testCodeJarDeployNotAffectedByChangedCodeHash() public {
        vm.deal(address(0xbab), 10 ether);
        bytes memory code = hex"11223344";
        bytes memory initCode = abi.encodePacked(hex"63", uint32(code.length), hex"80600e6000396000f3", code);
        address targetAddress = address(
            uint160(
                uint256(keccak256(abi.encodePacked(bytes1(0xff), address(codeJar), uint256(0), keccak256(initCode))))
            )
        );
        vm.startPrank(address(0xbab));
        // Attacker poison the target address so the codehash will be different
        targetAddress.call{value: 1 ether}("");
        vm.stopPrank();
        assertNotEq(targetAddress.codehash, 0);
        uint256 gasLeft = gasleft();
        // CodeJar will detect the codehash diff, but it will still be able to deploy the code
        address scriptAddress = codeJar.saveCode(code);
        uint256 gasUsed = gasLeft - gasleft();
        assertEq(scriptAddress.code, code);
        assertApproxEqAbs(gasUsed, 40000, 3000);
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
        bytes[] memory scripts = new bytes[](7);
        scripts[0] = hex"00";
        scripts[1] = hex"11";
        scripts[2] = hex"112233";
        scripts[3] = hex"00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff";
        scripts[4] = hex"00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff11";
        scripts[5] =
            hex"00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff";
        scripts[6] =
            hex"00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff11";

        for (uint8 i = 0; i < scripts.length; i++) {
            assertEq(codeJar.codeExists(scripts[i]), false);
            address codeAddress = codeJar.saveCode(scripts[i]);
            assertEq(codeAddress.code, scripts[i]);
            assertEq(codeJar.codeExists(scripts[i]), true);
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
        assertEq(zeroDeploy.code, hex"");

        address nonZeroDeploy = codeJar.saveCode(hex"00");
        assertEq(nonZeroDeploy.code, hex"00");
    }

    function testCodeJarCounter() public {
        address scriptAddress = codeJar.saveCode(type(Counter).runtimeCode);
        assertEq(scriptAddress.code, type(Counter).runtimeCode);

        Counter counter = Counter(scriptAddress);
        assertEq(counter.number(), 0);
        counter.increment();
        assertEq(counter.number(), 1);
    }

    function testCodeJarLarge() public {
        bytes32[] memory script = new bytes32[](10000);
        bytes memory code = abi.encodePacked(script);
        codeJar.saveCode(code);
    }

    function testCodeJarDeployConstructor() public {
        // This is the initCode used in CodeJar. It's a constructor code that returns "0xabcd".
        bytes memory contructorByteCode = abi.encodePacked(hex"63", hex"00000002", hex"80600e6000396000f3", hex"abcd");
        address scriptAddress = codeJar.saveCode(contructorByteCode);

        (bool success, bytes memory returnData) = scriptAddress.call(hex"");

        assertEq(returnData, hex"abcd");
    }

    function testCodeJarCodeExistsCorrectnessOnEmptyCodeAddressWithETH() public {
        bytes memory code = hex"";
        assertEq(codeJar.codeExists(code), false);
        bytes memory initCode = abi.encodePacked(hex"63", uint32(code.length), hex"80600e6000396000f3", code);
        address scriptAddress = address(
            uint160(
                uint256(keccak256(abi.encodePacked(bytes1(0xff), address(codeJar), uint256(0), keccak256(initCode))))
            )
        );
        vm.deal(address(this), 1 ether);
        scriptAddress.call{value: 1}("");

        // Ensure codeExists correctness holds for empty code with natvie token ETH
        assertEq(codeJar.codeExists(code), false);
    }

    // Note: cannot test code too large, as overflow impossible to test
}
