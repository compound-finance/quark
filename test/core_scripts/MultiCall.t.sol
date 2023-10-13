// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";
import "forge-std/interfaces/IERC20.sol";

import "./../../src/CodeJar.sol";
import "./../../src/QuarkWallet.sol";
import "./../../src/core_scripts/MultiCall.sol";
import "./../lib/YulHelper.sol";
import "./../lib/Counter.sol";
import "./scripts/SupplyComet.sol";
import "./interfaces/IComet.sol";

contract MultiCallTest is Test {
    CodeJar public codeJar;
    bytes32 internal constant QUARK_OPERATION_TYPEHASH =
        keccak256("QuarkOperation(bytes scriptSource,bytes scriptCalldata,uint256 nonce,uint256 expiry)");
    Counter public counter;

    function setUp() public {
        codeJar = new CodeJar();
        codeJar.saveCode(
            new YulHelper().getDeployed(
                "MultiCall.sol/MultiCall.json"
            )
        );

        counter = new Counter();
        counter.setNumber(0);
    }

    // Test #1: Invoke Counter twice via signature
    function testMultiCallCounter() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(address(this), codeJar);
        bytes memory multiCall = new YulHelper().getDeployed(
            "MultiCall.sol/MultiCall.json"
        );

        // Compose array of parameters
        address[] memory callContracts = new address[](2);
        bytes[] memory callCodes = new bytes[](2);
        bytes[] memory callDatas = new bytes[](2);
        uint256[] memory callValues = new uint256[](2);
        callContracts[0] = address(counter);
        callCodes[0] = hex"";
        callDatas[0] = abi.encodeCall(Counter.incrementBy, (20));
        callValues[0] = 0 wei;
        callContracts[1] = address(counter);
        callCodes[1] = hex"";
        callDatas[1] = abi.encodeCall(Counter.decrementBy, (5));
        callValues[1] = 0 wei;

        assertEq(counter.number(), 0);
        wallet.executeQuarkOperation(
            multiCall,
            abi.encodeWithSelector(MultiCall.run.selector, callContracts, callCodes, callDatas, callValues),
            false
        );

        assertEq(counter.number(), 15);
    }

    // Test #2: Supply ETH and withdraw USDC on Comet
    function testMultiCallSupplyEthAndWithdrawUSDC() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(address(this), codeJar);
        bytes memory multiCall = new YulHelper().getDeployed(
            "MultiCall.sol/MultiCall.json"
        );

        // Comet address in mainnet
        address cometAddr = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
        address USDCAddr = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        // Set up some funds for test
        deal(WETH, address(wallet), 100 ether);
        // Compose array of parameters
        address[] memory callContracts = new address[](3);
        bytes[] memory callCodes = new bytes[](3);
        bytes[] memory callDatas = new bytes[](3);
        uint256[] memory callValues = new uint256[](3);

        // Approve Comet to spend USDC
        callContracts[0] = address(WETH);
        callCodes[0] = hex"";
        callDatas[0] = abi.encodeCall(IERC20.approve, (cometAddr, 100 ether));
        callValues[0] = 0 wei;

        // Supply ETH to Comet
        callContracts[1] = address(cometAddr);
        callCodes[1] = hex"";
        callDatas[1] = abi.encodeCall(IComet.supply, (WETH, 100 ether));
        callValues[1] = 0 wei;

        // Withdraw USDC from Comet
        callContracts[2] = address(cometAddr);
        callCodes[2] = hex"";
        callDatas[2] = abi.encodeCall(IComet.withdraw, (USDCAddr, 1000_000_000));
        callValues[2] = 0 wei;

        wallet.executeQuarkOperation(
            multiCall,
            abi.encodeWithSelector(MultiCall.run.selector, callContracts, callCodes, callDatas, callValues),
            false
        );

        assertEq(IERC20(USDCAddr).balanceOf(address(wallet)), 1000_000_000);
    }

    // Test #3: MultiCall on runtime code in callcodes
    function testMultiCallSupplyCometViaRuntimeCodes() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(address(this), codeJar);
        bytes memory multiCall = new YulHelper().getDeployed(
            "MultiCall.sol/MultiCall.json"
        );

        // Comet address on mainnet
        address comet = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
        address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        // Set up some funds for test
        deal(USDC, address(wallet), 1000e6);
        // Compose array of parameters
        address[] memory callContracts = new address[](3);
        bytes[] memory callCodes = new bytes[](3);
        bytes[] memory callDatas = new bytes[](3);
        uint256[] memory callValues = new uint256[](3);
        callContracts[0] = address(USDC);
        callCodes[0] = hex"";
        callDatas[0] = abi.encodeCall(IERC20.approve, (comet, type(uint256).max));
        callValues[0] = 0 wei;
        callContracts[1] = address(0);
        callCodes[1] = type(SupplyComet).runtimeCode;
        callDatas[1] = abi.encodeCall(SupplyComet.supply, (comet, USDC, 500e6));
        callValues[1] = 0 wei;
        callContracts[2] = address(0);
        callCodes[2] = type(SupplyComet).runtimeCode;
        callDatas[2] = abi.encodeCall(SupplyComet.supply, (comet, USDC, 500e6));
        callValues[2] = 0 wei;
        // Approve Comet to spend USDC
        wallet.executeQuarkOperation(
            multiCall,
            abi.encodeWithSelector(MultiCall.run.selector, callContracts, callCodes, callDatas, callValues),
            false
        );

        // Since there is rouding diff, assert on diff is less than 10 wei
        assertLt(stdMath.delta(1000e6, IComet(comet).balanceOf(address(wallet))), 10);
    }
}