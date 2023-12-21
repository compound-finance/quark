// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdMath.sol";

import {QuarkFactory} from "quark-factory/src/QuarkFactory.sol";
import {CodeJar} from "codejar/src/CodeJar.sol";
import {QuarkWallet} from "quark-core/src/QuarkWallet.sol";
import {QuarkWalletProxyFactory} from "quark-proxy/src/QuarkWalletProxyFactory.sol";
import {QuarkStateManager} from "quark-core/src/QuarkStateManager.sol";
import {BatchExecutor} from "quark-core/src/periphery/BatchExecutor.sol";

contract QuarkFactoryTest is Test {
    QuarkFactory public factory;

    function setUp() public {
        factory = new QuarkFactory();
    }

    function testQuarkFactoryDeployToDeterministicAddresses() public {
        vm.pauseGasMetering();
        address expectedCodeJarAddress =
            getCreate2AddressHelper(address(factory), bytes32(0), abi.encodePacked(type(CodeJar).creationCode));
        address expectedQuarkStateManagerAddress = getCreate2AddressHelper(
            address(factory), bytes32(0), abi.encodePacked(type(QuarkStateManager).creationCode)
        );
        address expectedQuarkWalletImpAddress = getCreate2AddressHelper(
            address(factory),
            bytes32(0),
            abi.encodePacked(
                type(QuarkWallet).creationCode,
                abi.encode(expectedCodeJarAddress),
                abi.encode(expectedQuarkStateManagerAddress)
            )
        );
        address expectedQuarkWalletProxyFactoryAddress = getCreate2AddressHelper(
            address(factory),
            bytes32(0),
            abi.encodePacked(type(QuarkWalletProxyFactory).creationCode, abi.encode(expectedQuarkWalletImpAddress))
        );

        address expectedBatchExecutorAddress =
            getCreate2AddressHelper(address(factory), bytes32(0), abi.encodePacked(type(BatchExecutor).creationCode));

        vm.resumeGasMetering();
        factory.deployQuarkContracts();
        assertEq(address(factory.codeJar()), expectedCodeJarAddress);
        assertEq(address(factory.quarkWalletImp()), expectedQuarkWalletImpAddress);
        assertEq(address(factory.quarkWalletProxyFactory()), expectedQuarkWalletProxyFactoryAddress);
        assertEq(address(factory.quarkStateManager()), expectedQuarkStateManagerAddress);
        assertEq(address(factory.batchExecutor()), expectedBatchExecutorAddress);
    }

    function testQuarkFactoryDeployTwice() public {
        vm.pauseGasMetering();
        address expectedCodeJarAddress =
            getCreate2AddressHelper(address(factory), bytes32(0), abi.encodePacked(type(CodeJar).creationCode));
        address expectedQuarkStateManagerAddress = getCreate2AddressHelper(
            address(factory), bytes32(0), abi.encodePacked(type(QuarkStateManager).creationCode)
        );
        address expectedQuarkWalletImpAddress = getCreate2AddressHelper(
            address(factory),
            bytes32(0),
            abi.encodePacked(
                type(QuarkWallet).creationCode,
                abi.encode(expectedCodeJarAddress),
                abi.encode(expectedQuarkStateManagerAddress)
            )
        );
        address expectedQuarkWalletProxyFactoryAddress = getCreate2AddressHelper(
            address(factory),
            bytes32(0),
            abi.encodePacked(type(QuarkWalletProxyFactory).creationCode, abi.encode(expectedQuarkWalletImpAddress))
        );

        address expectedBatchExecutorAddress =
            getCreate2AddressHelper(address(factory), bytes32(0), abi.encodePacked(type(BatchExecutor).creationCode));

        vm.resumeGasMetering();
        factory.deployQuarkContracts();
        assertEq(address(factory.codeJar()), expectedCodeJarAddress);
        assertEq(address(factory.quarkWalletImp()), expectedQuarkWalletImpAddress);
        assertEq(address(factory.quarkWalletProxyFactory()), expectedQuarkWalletProxyFactoryAddress);
        assertEq(address(factory.quarkStateManager()), expectedQuarkStateManagerAddress);
        assertEq(address(factory.batchExecutor()), expectedBatchExecutorAddress);

        vm.expectRevert();
        factory.deployQuarkContracts();
    }

    function testInvariantAddressesBetweenNonces() public {
        vm.pauseGasMetering();
        address expectedCodeJarAddress =
            getCreate2AddressHelper(address(factory), bytes32(0), abi.encodePacked(type(CodeJar).creationCode));
        address expectedQuarkStateManagerAddress = getCreate2AddressHelper(
            address(factory), bytes32(0), abi.encodePacked(type(QuarkStateManager).creationCode)
        );
        address expectedQuarkWalletImpAddress = getCreate2AddressHelper(
            address(factory),
            bytes32(0),
            abi.encodePacked(
                type(QuarkWallet).creationCode,
                abi.encode(expectedCodeJarAddress),
                abi.encode(expectedQuarkStateManagerAddress)
            )
        );
        address expectedQuarkWalletProxyFactoryAddress = getCreate2AddressHelper(
            address(factory),
            bytes32(0),
            abi.encodePacked(type(QuarkWalletProxyFactory).creationCode, abi.encode(expectedQuarkWalletImpAddress))
        );

        address expectedBatchExecutorAddress =
            getCreate2AddressHelper(address(factory), bytes32(0), abi.encodePacked(type(BatchExecutor).creationCode));

        // Set a different nonce on the account, assuming some unaware ations done to the deployer eoa cuasing nonces to change
        vm.setNonce(address(this), 20);

        vm.resumeGasMetering();
        factory.deployQuarkContracts();
        assertEq(address(factory.codeJar()), expectedCodeJarAddress);
        assertEq(address(factory.quarkWalletImp()), expectedQuarkWalletImpAddress);
        assertEq(address(factory.quarkWalletProxyFactory()), expectedQuarkWalletProxyFactoryAddress);
        assertEq(address(factory.quarkStateManager()), expectedQuarkStateManagerAddress);
        assertEq(address(factory.batchExecutor()), expectedBatchExecutorAddress);
    }

    function getCreate2AddressHelper(address factoryAddress, bytes32 salt, bytes memory bytecode)
        public
        pure
        returns (address)
    {
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), factoryAddress, salt, keccak256(bytecode)))))
        );
    }
}
