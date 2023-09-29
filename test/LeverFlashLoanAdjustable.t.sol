// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";

import "../src/CodeJar.sol";
import "../src/QuarkWallet.sol";

import "./lib/YulHelper.sol";
import "./lib/LeverFlashLoanAdjustable.sol";
import "./../src/interfaces/IERC20NonStandard.sol";

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

    function testLeverFlashLoanAdjustable() public {
        address alice = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        // address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        // address Comet = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
        // uint collateralAmount = 1 ether;
        // deal(WETH, alice, collateralAmount);
        QuarkWallet wallet = new QuarkWallet{salt: 0}(alice, codeJar);

        // vm.startPrank(alice);
        // (bool success, ) = address(wallet).call{value: collateralAmount}("");
        // require(success, "Failed to send ether to wallet");
        // vm.stopPrank();
        deal(WETH, address(wallet), 1 ether);
        deal(WETH, alice, 10 ether);
        
        bytes memory leverFlashLoanAdjustable = new YulHelper().getDeployed(
            "LeverFlashLoanAdjustable.sol/LeverFlashLoanAdjustable.json"
        );

        Comet comet = Comet(0xc3d688B66703497DAA19211EEdff47f25384cdc3);

        vm.startPrank(alice);
        IERC20NonStandard(WETH).approve(0xc3d688B66703497DAA19211EEdff47f25384cdc3, type(uint256).max);
        IERC20NonStandard(USDC).approve(0xc3d688B66703497DAA19211EEdff47f25384cdc3, type(uint256).max);
        comet.supplyTo(address(wallet), WETH, 1e18);
        vm.stopPrank();
        vm.startPrank(address(wallet));
        IERC20NonStandard(WETH).approve(0xc3d688B66703497DAA19211EEdff47f25384cdc3, type(uint256).max);
        IERC20NonStandard(USDC).approve(0xc3d688B66703497DAA19211EEdff47f25384cdc3, type(uint256).max);
        vm.stopPrank();

        console.log("Before#1#Borrow balance of alice", comet.borrowBalanceOf(address(wallet)));
        console.log("Before#1#Collateral balance of alice", comet.collateralBalanceOf(address(wallet), WETH));
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: leverFlashLoanAdjustable,
            scriptCalldata: abi.encodeWithSelector(
                LeverFlashLoanAdjustable.runSlider.selector,
                comet,
                200
            ),
            nonce: 0,
            expiry: type(uint256).max,
            admitCallback: true
        });

        (uint8 v, bytes32 r, bytes32 s) = aliceSignature(wallet, op);

        bytes memory result = wallet.executeQuarkOperation(op, v, r, s);

        console.log("After#1#Borrow balance of alice", comet.borrowBalanceOf(address(wallet)));
        console.log("After#1#Collateral balance of alice", comet.collateralBalanceOf(address(wallet), WETH));

        // Alice increase to 400% leverage
        QuarkWallet.QuarkOperation memory op2 = QuarkWallet.QuarkOperation({
            scriptSource: leverFlashLoanAdjustable,
            scriptCalldata: abi.encodeWithSelector(
                LeverFlashLoanAdjustable.runSlider.selector,
                comet,
                400
            ),
            nonce: 1,
            expiry: type(uint256).max,
            admitCallback: true
        });

        (v,  r,  s) = aliceSignature(wallet, op2);

        result = wallet.executeQuarkOperation(op2, v, r, s);

        console.log("After#2#Borrow balance of alice", comet.borrowBalanceOf(address(wallet)));
        console.log("After#2#Collateral balance of alice", comet.collateralBalanceOf(address(wallet), WETH));
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
