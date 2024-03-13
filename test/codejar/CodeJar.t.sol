// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {YulHelper} from "test/lib/YulHelper.sol";

import {Counter} from "test/lib/Counter.sol";
import {TickCounter} from "test/lib/TickCounter.sol";
import {Mememe} from "test/lib/Mememe.sol";
import {ConstructorReverter} from "test/lib/ConstructorReverter.sol";
import {Redeployer} from "test/lib/Redeployer.sol";
import {Wacky, WackyBeacon, WackyCode, WackyFun} from "test/lib/Wacky.sol";

import {CodeJar} from "codejar/src/CodeJar.sol";

contract CodeJarTest is Test {
    event Ping(uint256 value);

    CodeJar public codeJar;
    address destructingAddress;
    WackyBeacon wackyBeacon;
    address wackyAddress;
    bytes destructingCode = hex"6000ff"; // PUSH1 [60]; 0 [00]; SELFDESTRUCT [FF]

    constructor() {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));
    }

    function setUp() public {
        // This setUp is only used for `testCodeJarSelfDestruct`. To test the state changes
        // from a selfdestruct in forge, the selfdestruct must be done in the setUp.
        // See: https://github.com/foundry-rs/foundry/issues/1543

        destructingAddress = codeJar.saveCode(new YulHelper().stub(destructingCode));
        assertEq(destructingAddress.code, destructingCode);
        (bool success,) = destructingAddress.call(hex"");
        assertEq(success, true);
        // Selfdestruct state changes do not take effect until after setUp
        assertEq(destructingAddress.code, destructingCode);

        wackyBeacon = new WackyBeacon();
        wackyBeacon.setCode(type(WackyCode).runtimeCode);
        wackyAddress = codeJar.saveCode(abi.encodePacked(type(Wacky).creationCode, abi.encode(wackyBeacon)));
        assertEq(wackyAddress.code, type(WackyCode).runtimeCode);
        assertEq(WackyCode(wackyAddress).hello(), 72);
        WackyCode(wackyAddress).destruct();
    }

    function testCodeJarSelfDestruct() public {
        assertEq(destructingAddress.code, hex"");
        assertEq(destructingAddress.codehash, 0);
        assertEq(destructingAddress, codeJar.saveCode(new YulHelper().stub(destructingCode)));
        assertEq(destructingAddress.code, destructingCode);
        assertEq(destructingAddress.codehash, keccak256(destructingCode));
    }

    function testCodeJarFirstDeploy() public {
        bytes memory stubbed = new YulHelper().stub(hex"11223344");
        uint256 gasLeft = gasleft();
        address scriptAddress = codeJar.saveCode(stubbed);
        uint256 gasUsed = gasLeft - gasleft();
        assertEq(scriptAddress.code, hex"11223344");
        assertApproxEqAbs(gasUsed, 42000, 3000);
    }

    function testCodeJarDeployNotAffectedByChangedCodeHash() public {
        // TODO: This test is more complex?
        vm.deal(address(0xbab), 10 ether);
        bytes memory code = hex"11223344";
        bytes memory initCode = new YulHelper().stub(code);
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
        address scriptAddress = codeJar.saveCode(initCode);
        uint256 gasUsed = gasLeft - gasleft();
        assertEq(scriptAddress.code, code);
        assertApproxEqAbs(gasUsed, 40000, 3000);
    }

    function testCodeJarSecondDeploy() public {
        bytes memory stubbed = new YulHelper().stub(hex"11223344");

        address scriptAddress = codeJar.saveCode(stubbed);

        uint256 gasLeft = gasleft();
        address scriptAddressNext = codeJar.saveCode(stubbed);
        uint256 gasUsed = gasLeft - gasleft();
        assertEq(scriptAddress, scriptAddressNext);
        assertEq(scriptAddressNext.code, hex"11223344");

        assertApproxEqAbs(gasUsed, 2000, 1000);
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
            assertEq(codeJar.codeExists(new YulHelper().stub(scripts[i])), false);
            address codeAddress = codeJar.saveCode(new YulHelper().stub(scripts[i]));
            assertEq(codeAddress.code, scripts[i]);
            assertEq(codeJar.codeExists(new YulHelper().stub(scripts[i])), true);
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

        // This cannot deploy now
        bytes memory stubbed = new YulHelper().stub(hex"");
        vm.expectRevert();
        address zeroDeploy = codeJar.saveCode(stubbed);
        assertEq(zeroDeploy.codehash, 0);
        assertEq(zeroDeploy.code, hex"");

        address nonZeroDeploy = codeJar.saveCode(new YulHelper().stub(hex"00"));
        assertEq(nonZeroDeploy.codehash, keccak256(hex"00"));
        assertEq(nonZeroDeploy.code, hex"00");
    }

    function testCodeJarCounter() public {
        address scriptAddress = codeJar.saveCode(type(Counter).creationCode);
        assertEq(scriptAddress.code, type(Counter).runtimeCode);

        Counter counter = Counter(scriptAddress);
        assertEq(counter.number(), 0);
        counter.increment();
        assertEq(counter.number(), 1);
    }

    function testCodeJarTickCounter() public {
        address scriptAddress = codeJar.saveCode(abi.encodePacked(type(TickCounter).creationCode, abi.encode(55)));

        // Note: runtime code is modified by immutable
        // assertEq(scriptAddress.code, type(Counter).runtimeCode);

        Counter counter = Counter(scriptAddress);
        assertEq(counter.number(), 55);
        counter.increment();
        assertEq(counter.number(), 56);
    }

    function testCodeJarStoresSelfReference() public {
        Mememe mememe = Mememe(codeJar.saveCode(type(Mememe).creationCode));

        vm.expectRevert("it's me, mario");
        mememe.hello();

        (bool success, bytes memory returnData) = address(mememe).delegatecall(abi.encodeCall(mememe.hello, ()));
        assert(success == true);

        assertEq(55, abi.decode(returnData, (uint256)));
    }

    function testCodeJarDeploysAnother() public {
        Redeployer redeployer = Redeployer(
            codeJar.saveCode(
                abi.encodePacked(
                    type(Redeployer).creationCode,
                    abi.encode(abi.encodePacked(type(TickCounter).creationCode, abi.encode(62)))
                )
            )
        );

        TickCounter counter = TickCounter(redeployer.deployed());

        assertEq(counter.number(), 62);
    }

    function testCodeJarLarge() public {
        bytes32[] memory script = new bytes32[](10000);
        bytes memory code = abi.encodePacked(script);
        codeJar.saveCode(new YulHelper().stub(code));
    }

    function testCodeJarRefusesToDeployEmptyCode() public {
        bytes memory code = hex"";
        assertEq(codeJar.codeExists(new YulHelper().stub(code)), false);
        bytes memory stubbed = new YulHelper().stub(code);
        vm.expectRevert();
        codeJar.saveCode(stubbed);
        assertEq(codeJar.codeExists(new YulHelper().stub(code)), false);
    }

    function testRevertsOnConstructorRevert() public {
        vm.expectRevert();
        codeJar.saveCode(type(ConstructorReverter).creationCode);
        assertEq(codeJar.codeExists(type(ConstructorReverter).creationCode), false);

        vm.expectRevert();
        codeJar.saveCode(type(ConstructorReverter).creationCode);
        assertEq(codeJar.codeExists(type(ConstructorReverter).creationCode), false);
    }

    function testCodeJarCanDeployCodeThatHadEthSent() public {
        bytes memory code = hex"112233";
        assertEq(codeJar.codeExists(new YulHelper().stub(code)), false);
        address codeAddress = codeJar.getCodeAddress(new YulHelper().stub(code));
        vm.deal(address(this), 1 ether);
        (bool success,) = codeAddress.call{value: 1}("");
        assertEq(success, true);

        // Ensure codeExists correctness holds for empty code with ETH
        assertEq(codeJar.codeExists(new YulHelper().stub(code)), false);
        assertEq(codeAddress.code, hex"");

        codeJar.saveCode(new YulHelper().stub(code));

        assertEq(codeJar.codeExists(new YulHelper().stub(code)), true);
        assertEq(codeAddress.code, code);
    }

    function testCodeJarCanBeWacky() public {
        wackyBeacon.setCode(type(WackyFun).runtimeCode);
        codeJar.saveCode(abi.encodePacked(type(Wacky).creationCode, abi.encode(wackyBeacon)));
        assertEq(wackyAddress.code, type(WackyFun).runtimeCode);
        assertEq(WackyFun(wackyAddress).cool(), 88);
    }

    function testRevertsOnSelfDestructingConstructor() public {
        vm.expectRevert();
        codeJar.saveCode(abi.encodePacked(type(WackyCode).creationCode));

        assertEq(codeJar.codeExists(abi.encodePacked(type(WackyCode).creationCode)), false);
    }
}
