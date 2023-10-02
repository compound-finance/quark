// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/QuarkWallet.sol";
import "../test/lib/YulHelper.sol";
import "solmate/tokens/ERC20.sol";
import "../test/lib/LeverFlashLoan.sol";

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
        uint collateralAmount = 1 ether;

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        QuarkWallet wallet = new QuarkWallet{salt: 0}(alice, codeJar);

        console.log("Quark wallet deployed to:", address(wallet));

        address(WETH).call{value: collateralAmount}("");

        ERC20(WETH).transfer(address(wallet), collateralAmount);

        bytes memory leverFlashLoan = yulHelper.getDeployed(
            "LeverFlashLoan.sol/LeverFlashLoan.json"
        );

        Comet comet = Comet(0xc3d688B66703497DAA19211EEdff47f25384cdc3);

        QuarkWallet.QuarkOperation memory op = QuarkWallet.QuarkOperation({
            scriptSource: leverFlashLoan,
            scriptCalldata: abi.encodeWithSelector(
                LeverFlashLoan.run.selector,
                comet,
                2,
                collateralAmount
            ),
            nonce: 0,
            expiry: 10695928823,
            admitCallback: true
        });

        (uint8 v, bytes32 r, bytes32 s) = aliceSignature(wallet, op);

        bytes memory result = wallet.executeQuarkOperation(op, v, r, s);

        uint borrowBalanceOfAlice = comet.borrowBalanceOf(address(wallet));
        console.log("Borrow balance of alice", borrowBalanceOfAlice);
        console.log("Starting collateral:", collateralAmount);
        console.log(
            "Ending collateral:",
            comet.userCollateral(address(wallet), WETH).balance
        );

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
