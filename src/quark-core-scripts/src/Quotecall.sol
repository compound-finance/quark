// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "quark-core-scripts/src/vendor/chainlink/AggregatorV3Interface.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title Quotecall Core Script
 * @notice Core script that executes an action via delegatecall and then pays for the gas using an ERC20 token.
 * @author Compound Labs, Inc.
 */
contract Quotecall {
    using SafeERC20 for IERC20;

    event PayForGas(address indexed payer, address indexed payee, address indexed paymentToken, uint256 amount);

    error BadPrice();
    error InvalidCallContext();
    error QuoteToleranceExceeded();

    /// @notice Native token (e.g. ETH) based price feed address (e.g. ETH/USD, ETH/BTC)
    address public immutable nativeTokenBasedPriceFeedAddress;

    /// @notice Payment token address
    address public immutable paymentTokenAddress;

    /// @notice The max delta precentage allowed between the quoted cost and actual cost of the call
    uint256 public immutable maxDeltaPercentage;

    /// @notice This contract's address
    address internal immutable scriptAddress;

    /// @notice Difference in scale between the native token + price feed and the payment token, used to scale the payment token
    uint256 internal immutable divisorScale;

    /// @notice Constant buffer for gas overhead
    /// This is a constant to account for the gas used by a Quark operation that is not tracked by the Quotecall contract itself
    /// Rough estimation: 30k for initial gas (21k + calldata gas) + 70k for Quark overhead
    uint256 internal constant GAS_OVERHEAD = 100_000;

    /// @dev The scale for percentages, used for `maxDeltaPercentage` (e.g. 1e18 = 100%)
    uint256 internal constant PERCENTAGE_SCALE = 1e18;

    /// @dev The number of decimals for the chain's native token
    uint256 internal constant NATIVE_TOKEN_DECIMALS = 18;

    /**
     * @notice Constructor
     * @param nativeTokenBasedPriceFeedAddress_ Native token based price feed address that follows Chainlink's AggregatorV3Interface correlated to the payment token
     * @param paymentTokenAddress_ Payment token address
     * @param maxDeltaPercentage_ Maximum allowed delta percentage between the quoted cost and actual cost of the call (1e18 = 100%)
     */
    constructor(address nativeTokenBasedPriceFeedAddress_, address paymentTokenAddress_, uint256 maxDeltaPercentage_) {
        nativeTokenBasedPriceFeedAddress = nativeTokenBasedPriceFeedAddress_;
        paymentTokenAddress = paymentTokenAddress_;
        maxDeltaPercentage = maxDeltaPercentage_;
        scriptAddress = address(this);

        // Note: Assumes the native token has 18 decimals
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
     * @param quotedAmount The quoted network fee for this transaction, in units of the payment token
     * @return Return data from call
     */
    function run(address callContract, bytes calldata callData, uint256 quotedAmount) external returns (bytes memory) {
        uint256 gasInitial = gasleft();
        // Ensures that this script cannot be called directly and self-destructed
        if (address(this) == scriptAddress) {
            revert InvalidCallContext();
        }

        IERC20(paymentTokenAddress).safeTransfer(tx.origin, quotedAmount);
        emit PayForGas(address(this), tx.origin, paymentTokenAddress, quotedAmount);

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
        uint256 actualAmount = gasUsed * tx.gasprice * uint256(price) / divisorScale;
        uint256 actualDelta = actualAmount > quotedAmount ? actualAmount - quotedAmount : quotedAmount - actualAmount;
        uint256 actualDeltaPercentage = actualDelta * PERCENTAGE_SCALE / quotedAmount;

        if (actualDeltaPercentage > maxDeltaPercentage) {
            revert QuoteToleranceExceeded();
        }

        return returnData;
    }
}
