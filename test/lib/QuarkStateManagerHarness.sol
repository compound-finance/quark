import {QuarkWallet} from "../../src/QuarkWallet.sol";
import {QuarkStateManager} from "../../src/QuarkStateManager.sol";

contract QuarkStateManagerHarness is QuarkStateManager {
    function readRawUnsafe(QuarkWallet wallet, uint96 nonce, string memory key) external view returns (bytes32) {
        return walletStorage[address(wallet)][nonce][keccak256(bytes(key))];
    }
}
