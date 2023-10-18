// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdMath.sol";
import "forge-std/interfaces/IERC20.sol";

import "./../../src/CodeJar.sol";
import "./../../src/QuarkWallet.sol";
import "./../../src/core_scripts/EthCall.sol";
import "./../lib/YulHelper.sol";
import "./../lib/SignatureHelper.sol";
import "./../lib/Counter.sol";
import "./scripts/SupplyComet.sol";
import "./interfaces/IComet.sol";

contract EthCallTest is Test {
    CodeJar public codeJar;
    Counter public counter;
    // Need alice info here, for signature to QuarkWallet
    address constant alice = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint256 constant alicePK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address constant comet = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    SignatureHelper public signatureHelper;

    function setUp() public {
        codeJar = new CodeJar();
        codeJar.saveCode(
            new YulHelper().getDeployed(
                "EthCall.sol/EthCall.json"
            )
        );

        counter = new Counter();
        counter.setNumber(0);
        signatureHelper = new SignatureHelper();
    }

    // Test Case #1: Invoke Counter contract via signature
    function testEthCallCounter() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(alice, codeJar);
        bytes memory ethcall = new YulHelper().getDeployed(
            "EthCall.sol/EthCall.json"
        );

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: ethcall,
            scriptCalldata: abi.encodeWithSelector(
                EthCall.run.selector, address(counter), abi.encodeCall(Counter.incrementBy, (1)), 0
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: true
        });

        assertEq(counter.number(), 0);
        (uint8 v, bytes32 r, bytes32 s) = signatureHelper.signOp(wallet, op, alicePK);
        wallet.executeQuarkOperation(op, v, r, s);
        assertEq(counter.number(), 1);
    }

    // Test Case #2: Supply USDC to Comet
    function testEthCallSupplyUSDCToComet() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(alice, codeJar);
        bytes memory ethcall = new YulHelper().getDeployed(
            "EthCall.sol/EthCall.json"
        );

        // Set up some funds for test
        deal(USDC, address(wallet), 1000e6);
        // Approve Comet to spend USDC
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: ethcall,
            scriptCalldata: abi.encodeWithSelector(
                EthCall.run.selector, address(USDC), abi.encodeCall(IERC20.approve, (comet, 1000e6)), 0
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (uint8 v, bytes32 r, bytes32 s) = signatureHelper.signOp(wallet, op, alicePK);
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(IComet(comet).balanceOf(address(wallet)), 0);
        // Supply Comet
        QuarkWallet.QuarkOperation memory op2 = QuarkWallet.QuarkOperation({
            scriptSource: ethcall,
            scriptCalldata: abi.encodeWithSelector(
                EthCall.run.selector, address(comet), abi.encodeCall(IComet.supply, (USDC, 1000e6)), 0
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (v, r, s) = signatureHelper.signOp(wallet, op2, alicePK);
        wallet.executeQuarkOperation(op2, v, r, s);

        // Since there is rouding diff, assert on diff is less than 10 wei
        assertLt(stdMath.delta(1000e6, IComet(comet).balanceOf(address(wallet))), 10);
    }

    // Test Case #3: Withdraw USDC from Comet
    function testEthCallWithdrawUSDCFromComet() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(address(alice), codeJar);
        bytes memory ethcall = new YulHelper().getDeployed(
            "EthCall.sol/EthCall.json"
        );

        // Set up some funds for test
        deal(WETH, address(wallet), 100 ether);

        QuarkWallet.QuarkOperation memory op;
        uint8 v;
        bytes32 r;
        bytes32 s;
        // Approve Comet to spend USDC
        op = QuarkWallet.QuarkOperation({
            scriptSource: ethcall,
            scriptCalldata: abi.encodeWithSelector(
                EthCall.run.selector, address(WETH), abi.encodeCall(IERC20.approve, (comet, 100 ether)), 0
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (v, r, s) = signatureHelper.signOp(wallet, op, alicePK);
        wallet.executeQuarkOperation(op, v, r, s);

        // Supply ETH to Comet
        op = QuarkWallet.QuarkOperation({
            scriptSource: ethcall,
            scriptCalldata: abi.encodeWithSelector(
                EthCall.run.selector, address(comet), abi.encodeCall(IComet.supply, (WETH, 100 ether)), 0
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (v, r, s) = signatureHelper.signOp(wallet, op, alicePK);
        wallet.executeQuarkOperation(op, v, r, s);

        // Withdraw USDC from Comet
        op = QuarkWallet.QuarkOperation({
            scriptSource: ethcall,
            scriptCalldata: abi.encodeWithSelector(
                EthCall.run.selector, address(comet), abi.encodeCall(IComet.withdraw, (USDC, 1000e6)), 0
                ),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false
        });
        (v, r, s) = signatureHelper.signOp(wallet, op, alicePK);
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(IERC20(USDC).balanceOf(address(wallet)), 1000e6);
    }
}
