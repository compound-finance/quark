// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";

import "./../../src/CodeJar.sol";
import "./../../src/QuarkWallet.sol";
import "./../../src/core_scripts/interfaces/IComet.sol";
import "./../../src/core_scripts/interfaces/IERC20.sol";
import "./../../src/core_scripts/Ethcall.sol";
import "./../lib/YulHelper.sol";
import "./../lib/Counter.sol";

contract EthcallTest is Test {
    CodeJar public codeJar;
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

    // Test Case #1: Invoke Counter contract via signature
    function testEthCallCounterBySig() public {
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

    // Test Case #2: Invoke Counter contract
    function testEthCallCounter() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(alice, codeJar);
        bytes memory ethcall = new YulHelper().getDeployed(
            "Ethcall.sol/Ethcall.json"
        );

        assertEq(counter.number(), 0);
        bytes memory result = wallet.executeQuarkOperation(
            ethcall,
            abi.encodeWithSelector(
                Ethcall.run.selector,
                address(counter),
                hex"",
                abi.encodeCall(
                    Counter.incrementBy,
                    (1)
                ),
                0
            ), 
            false
        );

        assertEq(counter.number(), 1);
    }

    // Test Case #3: Supply USDC to Comet
    function testSupplyUSDCToComet() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(alice, codeJar);
        bytes memory ethcall = new YulHelper().getDeployed(
            "Ethcall.sol/Ethcall.json"
        );

        // Comet address in mainnet
        address cometAddr = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
        address USDCAddr =  0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        // Set up some funds for test
        deal(USDCAddr, address(wallet), 1000_000_000);
        // Approve Comet to spend USDC
        wallet.executeQuarkOperation(
            ethcall,
            abi.encodeWithSelector(
                Ethcall.run.selector,
                address(USDCAddr),
                hex"",
                abi.encodeCall(
                    IERC20.approve,
                    (cometAddr, 1000_000_000)
                ),
                0
            ), 
            false
        );

        assertEq(IComet(cometAddr).balanceOf(address(wallet)), 0);
        // Supply Comet
        wallet.executeQuarkOperation(
            ethcall,
            abi.encodeWithSelector(
                Ethcall.run.selector,
                address(cometAddr),
                hex"",
                abi.encodeCall(
                    IComet.supply,
                    (USDCAddr, 1000_000_000)
                ),
                0
            ), 
            false
        );

        assertGt(IComet(cometAddr).balanceOf(address(wallet)), 0);
    }

    // Test Case #4: Withdraw USDC from Comet
    function testWithdrawUSDCFromComet() public {
        QuarkWallet wallet = new QuarkWallet{salt: 0}(alice, codeJar);
        bytes memory ethcall = new YulHelper().getDeployed(
            "Ethcall.sol/Ethcall.json"
        );

        // Comet address in mainnet
        address cometAddr = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
        address USDCAddr =  0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        // Set up some funds for test
        deal(WETH, address(wallet), 100 ether);
        // Approve Comet to spend USDC
        wallet.executeQuarkOperation(
            ethcall,
            abi.encodeWithSelector(
                Ethcall.run.selector,
                address(WETH),
                hex"",
                abi.encodeCall(
                    IERC20.approve,
                    (cometAddr, 100 ether)
                ),
                0
            ), 
            false
        );

        // Supply ETH to Comet
        wallet.executeQuarkOperation(
            ethcall,
            abi.encodeWithSelector(
                Ethcall.run.selector,
                address(cometAddr),
                hex"",
                abi.encodeCall(
                    IComet.supply,
                    (WETH, 100 ether)
                ),
                0
            ), 
            false
        );

        // Withdraw USDC from Comet
        wallet.executeQuarkOperation(
            ethcall,
            abi.encodeWithSelector(
                Ethcall.run.selector,
                address(cometAddr),
                hex"",
                abi.encodeCall(
                    IComet.withdraw,
                    (USDCAddr, 1000_000_000)
                ),
                0
            ), 
            false
        );

        assertEq(IERC20(USDCAddr).balanceOf(address(wallet)), 1000_000_000);
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
