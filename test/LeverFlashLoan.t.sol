// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";

import "../src/CodeJar.sol";
import "../src/QuarkWallet.sol";

import "./lib/YulHelper.sol";
import "./lib/LeverFlashLoan.sol";

contract LeverFlashLoanTest is Test {
    CodeJar public codeJar;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    bytes32 internal constant QUARK_OPERATION_TYPEHASH =
        keccak256(
            "QuarkOperation(bytes scriptSource,bytes scriptCalldata,uint256 nonce,uint256 expiry)"
        );

    function setUp() public {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        codeJar.saveCode(
            new YulHelper().getDeployed(
                "LeverFlashLoan.sol/LeverFlashLoan.json"
            )
        );
    }

    function testLeverFlashLoan() public {
        address alice = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        uint collateralAmount = 1 ether;
        // deal(WETH, alice, collateralAmount);
        QuarkWallet wallet = new QuarkWallet{salt: 0}(alice, codeJar);

        // vm.startPrank(alice);
        // (bool success, ) = address(wallet).call{value: collateralAmount}("");
        // require(success, "Failed to send ether to wallet");
        // vm.stopPrank();
        deal(WETH, address(wallet), collateralAmount);
        bytes memory leverFlashLoan = new YulHelper().getDeployed(
            "LeverFlashLoan.sol/LeverFlashLoan.json"
        );

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: leverFlashLoan,
            scriptCalldata: abi.encodeWithSelector(
                LeverFlashLoan.run.selector,
                Comet(0xc3d688B66703497DAA19211EEdff47f25384cdc3),
                2,
                collateralAmount
            ),
            nonce: 0,
            expiry: type(uint256).max,
            admitCallback: true
        });

        (uint8 v, bytes32 r, bytes32 s) = aliceSignature(wallet, op);

        bytes memory result = wallet.executeQuarkOperation(op, v, r, s);
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
