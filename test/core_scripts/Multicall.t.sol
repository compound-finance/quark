// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";
import "forge-std/interfaces/IERC20.sol";

import "./../../src/QuarkWallet.sol";
import "./../../src/QuarkWalletFactory.sol";
import "./../../src/core_scripts/MultiCall.sol";
import "./../lib/YulHelper.sol";
import "./../lib/SignatureHelper.sol";
import "./../lib/Counter.sol";
import "./interfaces/IComet.sol";

contract MultiCallTest is Test {
    QuarkWalletFactory public factory;
    Counter public counter;
    // For signature to QuarkWallet
    uint256 alicePK = 0xa11ce;
    address alice = vm.addr(alicePK);
    SignatureHelper public signatureHelper;

    // Comet address in mainnet
    address constant comet = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    // Uniswap router info on mainnet
    address constant uniswapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    function setUp() public {
        vm.createSelectFork(
            string.concat(
                "https://node-provider.compound.finance/ethereum-mainnet/", vm.envString("NODE_PROVIDER_BYPASS_KEY")
            )
        );
        factory = new QuarkWalletFactory();
        signatureHelper = new SignatureHelper();
        counter = new Counter();
        counter.setNumber(0);
    }

    function testInvokeCounterTwice() public {
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        bytes memory multiCall = new YulHelper().getDeployed(
            "MultiCall.sol/MultiCall.json"
        );

        // Compose array of parameters
        address[] memory callContracts = new address[](2);
        bytes[] memory callDatas = new bytes[](2);
        uint256[] memory callValues = new uint256[](2);
        callContracts[0] = address(counter);
        callDatas[0] = abi.encodeWithSignature("increment(uint256)", (20));
        callValues[0] = 0 wei;
        callContracts[1] = address(counter);
        callDatas[1] = abi.encodeWithSignature("decrement(uint256)", (5));
        callValues[1] = 0 wei;

        assertEq(counter.number(), 0);

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(MultiCall.run.selector, callContracts, callDatas, callValues),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false,
            isReplayable: false,
            requirements: new uint256[](0)
        });
        (uint8 v, bytes32 r, bytes32 s) = signatureHelper.signOp(alicePK, wallet, op);
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(counter.number(), 15);
    }

    function testSupplyWETHWithdrawUSDCOnComet() public {
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        bytes memory multiCall = new YulHelper().getDeployed(
            "MultiCall.sol/MultiCall.json"
        );

        // Set up some funds for test
        deal(WETH, address(wallet), 100 ether);

        // Compose array of parameters
        address[] memory callContracts = new address[](3);
        bytes[] memory callDatas = new bytes[](3);
        uint256[] memory callValues = new uint256[](3);

        // Approve Comet to spend USDC
        callContracts[0] = address(WETH);
        callDatas[0] = abi.encodeCall(IERC20.approve, (comet, 100 ether));
        callValues[0] = 0 wei;

        // Supply WETH to Comet
        callContracts[1] = comet;
        callDatas[1] = abi.encodeCall(IComet.supply, (WETH, 100 ether));
        callValues[1] = 0 wei;

        // Withdraw USDC from Comet
        callContracts[2] = comet;
        callDatas[2] = abi.encodeCall(IComet.withdraw, (USDC, 1000e6));
        callValues[2] = 0 wei;

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(MultiCall.run.selector, callContracts, callDatas, callValues),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false,
            isReplayable: false,
            requirements: new uint256[](0)
        });
        (uint8 v, bytes32 r, bytes32 s) = signatureHelper.signOp(alicePK, wallet, op);
        wallet.executeQuarkOperation(op, v, r, s);

        assertEq(IERC20(USDC).balanceOf(address(wallet)), 1000e6);
        assertEq(IComet(comet).collateralBalanceOf(address(wallet), WETH), 100 ether);
        assertApproxEqAbs(IComet(comet).borrowBalanceOf(address(wallet)), 1000e6, 2);
    }

    function testInvalidInput() public {
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        bytes memory multiCall = new YulHelper().getDeployed(
            "MultiCall.sol/MultiCall.json"
        );

        // Compose array of parameters
        address[] memory callContracts = new address[](2);
        bytes[] memory callDatas = new bytes[](1);
        uint256[] memory callValues = new uint256[](2);
        callContracts[0] = address(counter);
        callDatas[0] = abi.encodeWithSignature("increment(uint256)", (20));
        callValues[0] = 0 wei;
        callContracts[1] = address(counter);
        callValues[1] = 0 wei;

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(MultiCall.run.selector, callContracts, callDatas, callValues),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false,
            isReplayable: false,
            requirements: new uint256[](0)
        });
        (uint8 v, bytes32 r, bytes32 s) = signatureHelper.signOp(alicePK, wallet, op);

        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector, abi.encodeWithSelector(MultiCall.InvalidInput.selector)
            )
        );
        wallet.executeQuarkOperation(op, v, r, s);
    }

    function testMultiCallError() public {
        QuarkWallet wallet = QuarkWallet(factory.create(alice, 0));
        bytes memory multiCall = new YulHelper().getDeployed(
            "MultiCall.sol/MultiCall.json"
        );

        // Set up some funds for test
        deal(WETH, address(wallet), 100 ether);

        // Compose array of parameters
        address[] memory callContracts = new address[](4);
        bytes[] memory callDatas = new bytes[](4);
        uint256[] memory callValues = new uint256[](4);

        // Approve Comet to spend WETH
        callContracts[0] = address(WETH);
        callDatas[0] = abi.encodeCall(IERC20.approve, (comet, 100 ether));
        callValues[0] = 0 wei;

        // Supply WETH to Comet
        callContracts[1] = comet;
        callDatas[1] = abi.encodeCall(IComet.supply, (WETH, 100 ether));
        callValues[1] = 0 wei;

        // Withdraw USDC from Comet
        callContracts[2] = comet;
        callDatas[2] = abi.encodeCall(IComet.withdraw, (USDC, 1000e6));
        callValues[2] = 0 wei;

        // Send USDC to Stranger : Failed (insufficient balance)
        callContracts[3] = address(USDC);
        callDatas[3] = abi.encodeCall(IERC20.transfer, (address(123), 10000e6));
        callValues[3] = 0 wei;

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: multiCall,
            scriptCalldata: abi.encodeWithSelector(MultiCall.run.selector, callContracts, callDatas, callValues),
            nonce: wallet.nextUnusedNonce(),
            expiry: type(uint256).max,
            allowCallback: false,
            isReplayable: false,
            requirements: new uint256[](0)
        });
        (uint8 v, bytes32 r, bytes32 s) = signatureHelper.signOp(alicePK, wallet, op);
        vm.expectRevert(
            abi.encodeWithSelector(
                QuarkWallet.QuarkCallError.selector,
                abi.encodeWithSelector(
                    MultiCall.MultiCallError.selector,
                    3,
                    callContracts[3],
                    callDatas[3],
                    callValues[3],
                    abi.encodeWithSignature("Error(string)", "ERC20: transfer amount exceeds balance")
                )
            )
        );
        wallet.executeQuarkOperation(op, v, r, s);
    }
}
