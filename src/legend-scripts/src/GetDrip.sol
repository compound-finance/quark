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
    function drip(address faucet, address token) external {
        Fauceteer(faucet).drip(token);
    }
}
