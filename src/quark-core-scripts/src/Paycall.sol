// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "quark-core-scripts/src/vendor/chainlink/AggregatorV3Interface.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title Paycall Core Script
 * @notice Core script that executes an action via delegatecall and then pays for the gas using an ERC20 token.
 * @author Compound Labs, Inc.
 */
contract Paycall {
    using SafeERC20 for IERC20;

    event PayForGas(address indexed payer, address indexed payee, address indexed paymentToken, uint256 amount);

    error BadPrice();
    error InvalidCallContext();
    error TransactionTooExpensive();

    /// @notice Native token (e.g. ETH) based price feed address (e.g. ETH/USD, ETH/BTC)
    address public immutable nativeTokenBasedPriceFeedAddress;

    /// @notice Payment token address
    address public immutable paymentTokenAddress;

    /// @notice This contract's address
    address internal immutable scriptAddress;

    /// @notice Difference in scale between the native token + price feed and the payment token, used to scale the payment token
    uint256 internal immutable divisorScale;

    /// @notice Constant buffer for gas overhead
    /// This is a constant to account for the gas used by a Quark operation that is not tracked by the Paycall contract itself
    /// Rough estimation: 30k for initial gas (21k + calldata gas) + 70k for Quark overhead + 35k for ERC20 transfer
    uint256 internal constant GAS_OVERHEAD = 135_000;

    /// @dev The number of decimals for the chain's native token
    uint256 internal constant NATIVE_TOKEN_DECIMALS = 18;

    /**
     * @notice Constructor
     * @param nativeTokenBasedPriceFeedAddress_ Native token price feed address that follows Chainlink's AggregatorV3Interface correlated to the payment token
     * @param paymentTokenAddress_ Payment token address
     */
    constructor(address nativeTokenBasedPriceFeedAddress_, address paymentTokenAddress_) {
        nativeTokenBasedPriceFeedAddress = nativeTokenBasedPriceFeedAddress_;
        paymentTokenAddress = paymentTokenAddress_;
        scriptAddress = address(this);

        divisorScale = 10
            ** uint256(
                NATIVE_TOKEN_DECIMALS + AggregatorV3Interface(nativeTokenBasedPriceFeedAddress).decimals()
                    - IERC20Metadata(paymentTokenAddress).decimals()
            );
    }

    /**
     * @notice Execute delegatecall on a contract and pay tx.origin for gas
     * @param callContract Contract to call
     * @param callData Encoded calldata for call
     * @param maxPaymentCost The maximum amount of payment tokens allowed for this transaction
     * @return Return data from call
     */
    function run(address callContract, bytes calldata callData, uint256 maxPaymentCost)
        external
        returns (bytes memory)
    {
        uint256 gasInitial = gasleft();
        // Ensures that this script cannot be called directly and self-destructed
        if (address(this) == scriptAddress) {
            revert InvalidCallContext();
        }

        (bool success, bytes memory returnData) = callContract.delegatecall(callData);
        if (!success) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }

        (, int256 price,,,) = AggregatorV3Interface(nativeTokenBasedPriceFeedAddress).latestRoundData();
        if (price <= 0) {
            revert BadPrice();
        }

        uint256 gasUsed = gasInitial - gasleft() + GAS_OVERHEAD;
        uint256 paymentAmount = gasUsed * tx.gasprice * uint256(price) / divisorScale;
        if (paymentAmount > maxPaymentCost) {
            revert TransactionTooExpensive();
        }
        IERC20(paymentTokenAddress).safeTransfer(tx.origin, paymentAmount);
        emit PayForGas(address(this), tx.origin, paymentTokenAddress, paymentAmount);

        return returnData;
    }
}
