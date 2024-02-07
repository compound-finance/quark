pragma solidity 0.8.23;

// To handle loading up new accounts on stage and dev
interface Fauceteer {
    function drip(address token) external;

    error BalanceTooLow();
    error RequestedTooFrequently();
    error TransferFailed();
}

contract GetDrip {
    /**
     *   @notice Drip tokens from goerli faucet
     */
    function drip(address token) external {
        Fauceteer(0x75442Ac771a7243433e033F3F8EaB2631e22938f).drip(token);
    }
}
