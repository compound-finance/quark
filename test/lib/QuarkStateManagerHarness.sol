import {QuarkWallet} from "../../src/QuarkWallet.sol";
import {QuarkStateManager} from "../../src/QuarkStateManager.sol";

contract QuarkStateManagerHarness is QuarkStateManager {
    function setNonceExternal(uint96 nonce) external {
        // NOTE: intentionally violates invariant in the name of... testing
        activeNonceScript[msg.sender] = NonceScript({nonce: nonce, scriptAddress: address(0)});
        // NOTE: getBucket asserts that the nonce is active; otherwise, reverts
        (uint256 bucket, uint256 setMask) = getBucket(nonce);
        nonces[msg.sender][bucket] |= setMask;
        activeNonceScript[msg.sender] = NonceScript({nonce: 0, scriptAddress: address(0)});
    }

    function readRawUnsafe(QuarkWallet wallet, uint96 nonce, string memory key) external view returns (bytes32) {
        return walletStorage[address(wallet)][nonce][keccak256(bytes(key))];
    }
}
