// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";

import "./../../src/CodeJar.sol";
import "./../../src/QuarkWallet.sol";
import "./../../src/core_scripts/Ethcall.sol";
import "./../lib/YulHelper.sol";
import "./../lib/Counter.sol";

contract EthcallTest is Test {
    CodeJar public codeJar;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    bytes32 internal constant QUARK_OPERATION_TYPEHASH =
        keccak256(
            "QuarkOperation(bytes scriptSource,bytes scriptCalldata,uint256 nonce,uint256 expiry)"
        );
    Counter public counter;
    // Need alice info here, for signature to QuarkWallet
    address alice = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint256 alicePK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    function setUp() public {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        codeJar.saveCode(
            new YulHelper().getDeployed(
                "Ethcall.sol/Ethcall.json"
            )
        );

        counter = new Counter();
        counter.setNumber(0);
        console.log("Counter deployed to : %s", address(counter));
    }

    function testEthCallCounter() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(alice, codeJar);
        bytes memory ethcall = new YulHelper().getDeployed(
            "Ethcall.sol/Ethcall.json"
        );

        
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: ethcall,
            scriptCalldata: abi.encodeWithSelector(
                Ethcall.run.selector,
                address(counter),
                hex"",
                abi.encodeCall(
                    Counter.incrementBy,
                    (1)
                ),
                0
            ),
            nonce: 0,
            expiry: type(uint256).max,
            admitCallback: true
        });

        assertEq(counter.number(), 0);
        (uint8 v, bytes32 r, bytes32 s) = aliceSignature(wallet, op);
        bytes memory result = wallet.executeQuarkOperation(op, v, r, s);
        assertEq(counter.number(), 1);
    }



    function aliceSignature(
        QuarkWallet wallet,
        QuarkWallet.QuarkOperation memory op
    ) internal view returns (uint8, bytes32, bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                QUARK_OPERATION_TYPEHASH,
                op.scriptSource,
                op.scriptCalldata,
                op.nonce,
                op.expiry
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", wallet.DOMAIN_SEPARATOR(), structHash)
        );
        return
            vm.sign(
                // ALICE PRIVATE KEY
                0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80,
                digest
            );
    }
}
