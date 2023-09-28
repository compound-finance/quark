// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../../src/CodeJar.sol";
import "../../src/QuarkWallet.sol";
import "../lib/YulHelper.sol";

import "../../src/interface/CometInterface.sol";
import "../../src/interface/IWETH.sol";
import "../../src/interface/IUSDC.sol";
import "../../src/interface/IWBTC.sol";

import "../../src/core_scripts/Rebalance.sol";

contract RebalanceTest is Test {

    CodeJar public codeJar;

    bytes32 internal constant QUARK_OPERATION_TYPEHASH =
        keccak256(
            "QuarkOperation(bytes scriptSource,bytes scriptCalldata,uint256 nonce,uint256 expiry)"
        );

    uint128 public constant ASSET1_PRICE_USDC = 1400;
    uint128 public constant ASSET2_PRICE_USDC = 27000;
    uint128 public constant ASSET1_DECIMALS = 18;
    uint128 public constant ASSET2_DECIMALS = 8;

    address public constant COMET_ADDRESS = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address public constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant WBTC_ADDRESS = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public rebalanceTrxScript;

    QuarkWallet public wallet;
    bytes rebalance;

    address public constant ALICE = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    event Portfolio(uint128 asset1BalanceInUSDC, uint128 asset2BalanceInUSDC, uint targetWeight, uint currentWeight);

    function setUp() public  {
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        rebalanceTrxScript = codeJar.saveCode(
            new YulHelper().getDeployed(
                "Rebalance.sol/Rebalance.json"
            )
        );

        wallet = new QuarkWallet{salt: 0}(ALICE, codeJar);

        rebalance = new YulHelper().getDeployed("Rebalance.sol/Rebalance.json");

        // ALICE approves WETH and WBTC for Comet
        vm.startPrank(ALICE);
        IWeth9(WETH_ADDRESS).approve(COMET_ADDRESS, type(uint256).max);
        IWBTC(WBTC_ADDRESS).approve(COMET_ADDRESS, type(uint256).max);
        vm.stopPrank();

        // QuarkWallet approves WETH and WBTC for Comet
        vm.startPrank(address(wallet));
        IWeth9(WETH_ADDRESS).approve(COMET_ADDRESS, type(uint256).max);
        IWBTC(WBTC_ADDRESS).approve(COMET_ADDRESS, type(uint256).max);
        vm.stopPrank();
    }

    // portfolio is 60-40 WETH-WBTC, so sell WETH and then supply WBTC
    function testRebalanceSellAsset1() public {
        // GIVE ALICE SOME WETH AND WBTC AND HAVE HER SUPPLY TO COMET
        uint wethAmount = 29 * (10 ** 18);
        uint wbtcAmount = 1 * (10 ** 8);
        deal(WETH_ADDRESS, ALICE, wethAmount);
        deal(WBTC_ADDRESS, ALICE, wbtcAmount);

        vm.startPrank(ALICE);
        CometInterface(COMET_ADDRESS).supplyTo(address(wallet), WETH_ADDRESS, wethAmount);
        CometInterface(COMET_ADDRESS).supplyTo(address(wallet), WBTC_ADDRESS, wbtcAmount);
        vm.stopPrank();

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: rebalance,
            scriptCalldata: abi.encodeWithSelector(
                Rebalance.rebalance.selector,
                COMET_ADDRESS,
                WETH_ADDRESS,
                WBTC_ADDRESS,
                50, // asset1Weight = 50%
                10 // threshold = 10%
            ),
            nonce: 0,
            expiry: type(uint256).max,
            admitCallback: true
        });

        (uint8 v, bytes32 r, bytes32 s) = _aliceSignature(wallet, op);

        wallet.executeQuarkOperation(op, v, r, s);
    }

    // portfolio is 37-63 WETH-WBTC, so sell WBTC and then supply WETH
    function testRebalanceSellAsset2() public {
        // GIVE ALICE SOME WETH AND WBTC AND HAVE HER SUPPLY TO COMET
        uint wethAmount = 20 * (10 ** 18);
        uint wbtcAmount = 1.7 * (10 ** 8);
        deal(WETH_ADDRESS, ALICE, wethAmount);
        deal(WBTC_ADDRESS, ALICE, wbtcAmount);

        vm.startPrank(ALICE);
        CometInterface(COMET_ADDRESS).supplyTo(address(wallet), WETH_ADDRESS, wethAmount);
        CometInterface(COMET_ADDRESS).supplyTo(address(wallet), WBTC_ADDRESS, wbtcAmount);
        vm.stopPrank();

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: rebalance,
            scriptCalldata: abi.encodeWithSelector(
                Rebalance.rebalance.selector,
                COMET_ADDRESS,
                WETH_ADDRESS,
                WBTC_ADDRESS,
                50, // asset1Weight = 50%
                10 // threshold = 10%
            ),
            nonce: 0,
            expiry: type(uint256).max,
            admitCallback: true
        });

        (uint8 v, bytes32 r, bytes32 s) = _aliceSignature(wallet, op);

        wallet.executeQuarkOperation(op, v, r, s);
    }

    // portfolio is roughly 50-50 so does not rebalance
    function testRevertIfNotRebalanceable() public {
        // GIVE ALICE SOME WETH AND WBTC AND HAVE HER SUPPLY TO COMET
        uint wethAmount = 20 * (10 ** 18);
        uint wbtcAmount = 1 * (10 ** 8);
        deal(WETH_ADDRESS, ALICE, wethAmount);
        deal(WBTC_ADDRESS, ALICE, wbtcAmount);

        vm.startPrank(ALICE);
        CometInterface(COMET_ADDRESS).supplyTo(address(wallet), WETH_ADDRESS, wethAmount);
        CometInterface(COMET_ADDRESS).supplyTo(address(wallet), WBTC_ADDRESS, wbtcAmount);
        vm.stopPrank();

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: rebalance,
            scriptCalldata: abi.encodeWithSelector(
                Rebalance.rebalance.selector,
                COMET_ADDRESS,
                WETH_ADDRESS,
                WBTC_ADDRESS,
                50, // asset1Weight = 50%
                10 // threshold = 10%
            ),
            nonce: 0,
            expiry: type(uint256).max,
            admitCallback: true
        });

        (uint8 v, bytes32 r, bytes32 s) = _aliceSignature(wallet, op);

        vm.expectRevert();
        wallet.executeQuarkOperation(op, v, r, s);
    }

    function _aliceSignature(QuarkWallet _wallet, QuarkWallet.QuarkOperation memory op) internal view returns (uint8, bytes32, bytes32) {
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
            abi.encodePacked("\x19\x01", _wallet.DOMAIN_SEPARATOR(), structHash)
        );

        return
            vm.sign(
                // ALICE PRIVATE KEY
                0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80,
                digest
            );
    }
}