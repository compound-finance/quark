// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./lib/YulHelper.sol";
import "./lib/Counter.sol";

import "../src/QuarkWallet.sol";
import "../src/QuarkWalletFactory.sol";

contract QuarkWalletFactoryTest is Test {
    event WalletDeploy(address indexed account, address indexed walletAddress, bytes32 salt);

    QuarkWalletFactory public factory;
    Counter public counter;

    uint256 alicePrivateKey = 0xa11ce;
    address alice; // see setup()
    address bob = address(11);

    bytes32 internal constant QUARK_OPERATION_TYPEHASH = keccak256(
        "QuarkOperation(bytes scriptSource,bytes scriptCalldata,uint256 nonce,uint256 expiry,bool allowCallback)"
    );

    bytes32 internal constant QUARK_WALLET_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    constructor() {
        factory = new QuarkWalletFactory();
        console.log("QuarkWalletFactory deployed to: %s", address(factory));

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to: %s", address(counter));

        alice = vm.addr(alicePrivateKey);
    }

    function domainSeparatorForAccount(address account, bytes32 salt) public view returns (bytes32) {
        address walletAddress = factory.walletAddressForAccount(account, salt);
        return keccak256(
            abi.encode(
                QUARK_WALLET_DOMAIN_TYPEHASH,
                keccak256(bytes("Quark Wallet")), // name
                keccak256(bytes("1")), // version
                block.chainid,
                walletAddress
            )
        );
    }

    function aliceSignature(QuarkWallet.QuarkOperation memory op) internal view returns (uint8, bytes32, bytes32) {
        return aliceSignature(op, 0);
    }

    function aliceSignature(QuarkWallet.QuarkOperation memory op, bytes32 salt)
        internal
        view
        returns (uint8, bytes32, bytes32)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                QUARK_OPERATION_TYPEHASH, op.scriptSource, op.scriptCalldata, op.nonce, op.expiry, op.allowCallback
            )
        );
        bytes32 walletDomainSeparator = domainSeparatorForAccount(alice, salt);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", walletDomainSeparator, structHash));
        return vm.sign(alicePrivateKey, digest);
    }

    function testVersion() public {
        assertEq(factory.VERSION(), 1);
    }

    function testCreatesCodejar() public {
        assertNotEq(address(factory.codeJar()), address(0));
    }

    function testCreatesWalletAtDeterministicAddress() public {
        vm.expectEmit(true, true, true, true);
        emit WalletDeploy(alice, factory.walletAddressForAccount(alice), bytes32(0));
        address aliceWallet = factory.create(alice);
        assertEq(aliceWallet, factory.walletAddressForAccount(alice));
    }

    function testCreateRevertsOnRepeat() public {
        vm.expectEmit(true, true, true, true);
        emit WalletDeploy(alice, factory.walletAddressForAccount(alice), bytes32(0));
        factory.create(alice);
        vm.expectRevert();
        factory.create(alice);
    }

    function testCreateAdditionalWalletWithSalt() public {
        // inital wallet is created
        vm.expectEmit(true, true, true, true);
        emit WalletDeploy(alice, factory.walletAddressForAccount(alice), bytes32(0));
        factory.create(alice);

        // it is created with 0 as salt (and therefore reverts on a repeated attempt)
        vm.expectRevert();
        factory.create(alice, 0);

        // but the user can pass in a salt and create additional wallets
        address aliceSaltWallet = factory.create(alice, bytes32("1"));
        assertEq(aliceSaltWallet, factory.walletAddressForAccount(alice, bytes32("1")));
    }

    function testCreateAndExecuteCreatesWallet() public {
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: incrementer,
            scriptCalldata: abi.encodeWithSignature("incrementCounter(address)", counter),
            nonce: 0,
            expiry: block.timestamp + 1000,
            allowCallback: false
        });

        // alice signs the operation
        (uint8 v, bytes32 r, bytes32 s) = aliceSignature(op);

        assertEq(counter.number(), 0);

        // operation is executed
        vm.expectEmit(true, true, true, true);
        // it creates a wallet
        emit WalletDeploy(alice, factory.walletAddressForAccount(alice), bytes32(0));
        factory.createAndExecute(alice, op, v, r, s);

        // operation was executed
        assertEq(counter.number(), 3);

        // uses up the operation's nonce
        address walletAddress = factory.walletAddressForAccount(alice);
        assertEq(
            QuarkWallet(walletAddress).storageManager().isNonceSet(walletAddress, 0),
            true
        );
    }

    function testCreateAndExecuteWithSalt() public {
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: incrementer,
            scriptCalldata: abi.encodeWithSignature("incrementCounter(address)", counter),
            nonce: 0,
            expiry: block.timestamp + 1000,
            allowCallback: false
        });

        bytes32 salt = bytes32("salty salt salt");

        // alice signs the operation
        (uint8 v, bytes32 r, bytes32 s) = aliceSignature(op, salt);

        assertEq(counter.number(), 0);

        // operation is executed
        vm.expectEmit(true, true, true, true);
        // it creates a wallet (with salt)
        emit WalletDeploy(alice, factory.walletAddressForAccount(alice, salt), salt);
        factory.createAndExecute(alice, salt, op, v, r, s);

        // operation was executed
        assertEq(counter.number(), 3);

        // uses up the operation's nonce
        address walletAddress = factory.walletAddressForAccount(alice);
        assertEq(
            QuarkWallet(walletAddress).storageManager().isNonceSet(walletAddress, 0),
            true
        );
    }

    function testExecuteOnExistingWallet() public {
        bytes memory incrementer = new YulHelper().getDeployed("Incrementer.sol/Incrementer.json");

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: incrementer,
            scriptCalldata: abi.encodeWithSignature("incrementCounter(address)", counter),
            nonce: 0,
            expiry: block.timestamp + 1000,
            allowCallback: false
        });

        // alice signs the operation
        (uint8 v, bytes32 r, bytes32 s) = aliceSignature(op);

        assertEq(counter.number(), 0);

        // the wallet is deployed
        vm.expectEmit(true, true, true, true);
        emit WalletDeploy(alice, factory.walletAddressForAccount(alice), bytes32(0));
        factory.create(alice);

        // operation is executed
        factory.createAndExecute(alice, op, v, r, s);

        // operation was executed
        assertEq(counter.number(), 3);

        // uses up the operation's nonce
        address walletAddress = factory.walletAddressForAccount(alice);
        assertEq(
            QuarkWallet(walletAddress).storageManager().isNonceSet(walletAddress, 0),
            true
        );
    }
}
