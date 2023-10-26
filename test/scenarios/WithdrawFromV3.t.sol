// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";
import "forge-std/StdMath.sol";

import "./../../src/QuarkWallet.sol";
import "./../../src/QuarkWalletFactory.sol";
import "./../../src/terminal_scripts/TerminalScript.sol";
import "./../lib/YulHelper.sol";
import "./../lib/SignatureHelper.sol";
import "./../lib/Counter.sol";

/**
 * Scenario test for uesr borrow base asset from Comet v3 market
 */
contract BorrowFromV3 is Test {
    QuarkWalletFactory public factory;
    Counter public counter;
    uint256 alicePrivateKey = 0xa11ce;
    address alice = vm.addr(alicePrivateKey);

    // Contracts address on mainnet
    address constant comet = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function setUp() public {
        // Fork setup
        vm.createSelectFork(
            string.concat(
                "https://node-provider.compound.finance/ethereum-mainnet/", vm.envString("NODE_PROVIDER_BYPASS_KEY")
            ),
            18429607 // 2023-10-25 13:24:00 PST
        );
        factory = new QuarkWalletFactory();
    }

    function testWithdrawTerminalScript() public {
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        bytes memory ethcall = new YulHelper().getDeployed(
            "TerminalScript.sol/TerminalScript.json"
        );

        deal(WETH, address(wallet), 10 ether);

        vm.startPrank(address(wallet));
        IERC20(WETH).approve(comet, 10 ether);
        IComet(comet).supply(WETH, 10 ether);
        vm.stopPrank();

        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 10 ether);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 0 ether);
        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: ethcall,
            scriptCalldata: abi.encodeWithSelector(TerminalScript.withdrawFromComet.selector, comet, WETH, 10 ether),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false,
            isReplayable: false,
            requirements: new uint256[](0)
        });

        (uint8 v, bytes32 r, bytes32 s) = new SignatureHelper().signOp(alicePrivateKey, wallet, op);
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 0 ether);
        assertEq(IERC20(WETH).balanceOf(address(wallet)), 10 ether);
    }
}
