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
        bytes[] memory scripts = new bytes[](9);
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
        scripts[8] =
            hex"608060405234801561001057600080fd5b50600436106100365760003560e01c80636b582b7614610056578063e5910ae714610069575b73f62849f9a0b5bf2913b396098f7c7019b51a820a61005481610077565b005b610054610064366004610230565b610173565b610054610077366004610230565b806001600160a01b031663d09de08a6040518163ffffffff1660e01b8152600401600060405180830381600087803b1580156100b257600080fd5b505af11580156100c6573d6000803e3d6000fd5b50505050806001600160a01b031663d09de08a6040518163ffffffff1660e01b8152600401600060405180830381600087803b15801561010557600080fd5b505af1158015610119573d6000803e3d6000fd5b50505050806001600160a01b031663d09de08a6040518163ffffffff1660e01b8152600401600060405180830381600087803b15801561015857600080fd5b505af115801561016c573d6000803e3d6000fd5b5050505050565b61017c81610077565b306001600160a01b0316632e716fb16040518163ffffffff1660e01b8152600401602060405180830381865afa1580156101ba573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906101de9190610254565b6001600160a01b0316631913592a6040518163ffffffff1660e01b8152600401600060405180830381600087803b15801561015857600080fd5b6001600160a01b038116811461022d57600080fd5b50565b60006020828403121561024257600080fd5b813561024d81610218565b9392505050565b60006020828403121561026657600080fd5b815161024d8161021856fea164736f6c6343000813000a";

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

    // Note: cannot test code too large, as overflow impossible to test
}
