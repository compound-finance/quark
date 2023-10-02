// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/QuarkWallet.sol";
import "../test/lib/YulHelper.sol";
import "solmate/tokens/ERC20.sol";
import "../src/interfaces/IERC20NonStandard.sol";
import "../test/lib/LeverFlashLoanAdjustable.sol";

contract CounterScript is Script {
    CodeJar public codeJar;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    bytes32 internal constant QUARK_OPERATION_TYPEHASH =
        keccak256(
            "QuarkOperation(bytes scriptSource,bytes scriptCalldata,uint256 nonce,uint256 expiry)"
        );
    YulHelper yulHelper;

    function setUp() public {
        yulHelper = new YulHelper();

        vm.allowCheatcodes(address(yulHelper));
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        codeJar = new CodeJar();
        console.log("CodeJar deployed to: %s", address(codeJar));

        codeJar.saveCode(
            yulHelper.getDeployed("LeverFlashLoan.sol/LeverFlashLoan.json")
        );

        vm.stopBroadcast();
    }

    function run() public {
        address alice = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        QuarkWallet wallet = QuarkWallet(
            payable(0x1D56181D9f99F36340b67Ae6435Cc4A0aCa3B822)
        );

        bytes memory leverFlashLoanAdjustable = yulHelper.getDeployed(
            "LeverFlashLoanAdjustable.sol/LeverFlashLoanAdjustable.json"
        );
        Comet comet = Comet(0xc3d688B66703497DAA19211EEdff47f25384cdc3);

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: leverFlashLoanAdjustable,
            scriptCalldata: abi.encodeWithSelector(
                LeverFlashLoanAdjustable.runSlider.selector,
                comet,
                300
            ),
            nonce: 2,
            expiry: type(uint256).max,
            admitCallback: true
        });

        (uint8 v, bytes32 r, bytes32 s) = aliceSignature(wallet, op);

        bytes memory result = wallet.executeQuarkOperation(op, v, r, s);

        vm.stopBroadcast();
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
