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

    error InvalidCallContext();
    error TransactionOutsideQuote();

    /// @notice This contract's address
    address internal immutable scriptAddress;

    /// @notice ETH based price feed address (i.e. ETH/USD, ETH/BTC)
    address public immutable ethBasedPriceFeedAddress;

    /// @notice Payment token address
    address public immutable paymentTokenAddress;

    /// @notice The max delta in basis points
    uint256 public immutable maxDelta;

    /// @notice Constant buffer for gas overhead
    /// This is a constant to accounted for the gas used by the Quotecall contract itself that's not tracked by gasleft()
    uint256 internal constant GAS_OVERHEAD = 75000;

    /// @notice Difference in scale between the payment token and ETH, used to scale the payment token.
    /// Will be used to scale decimals to the correct amount for payment token
    uint256 internal immutable divisorScale;

    /**
     * @notice Constructor
     * @param ethPriceFeed Eth based price feed address that follows Chainlink's AggregatorV3Interface correlated to the payment token
     * @param paymentToken Payment token address
     * @param maxDeltaBps Maximal allowed delta in basis points (100 bps = 1%)
     */
    constructor(address ethPriceFeed, address paymentToken, uint256 maxDeltaBps) {
        ethBasedPriceFeedAddress = ethPriceFeed;
        paymentTokenAddress = paymentToken;
        scriptAddress = address(this);
        maxDelta = maxDeltaBps;

        divisorScale = 10
            ** uint256(
                18 + AggregatorV3Interface(ethBasedPriceFeedAddress).decimals()
                    - IERC20Metadata(paymentTokenAddress).decimals()
            );
    }

    /**
     * @notice Execute delegatecall on a contract and pay tx.origin for gas
     * @param callContract Contract to call
     * @param callData Encoded calldata for call
     * @param quote The quoted network fee for this transaction
     * @return Return data from call
     */
    function run(address callContract, bytes calldata callData, uint256 quote)
        external
        returns (bytes memory)
    {
        uint256 gasInitial = gasleft();
        // Ensures that this script cannot be called directly and self-destructed
        if (address(this) == scriptAddress) {
            revert InvalidCallContext();
        }

        IERC20(paymentTokenAddress).safeTransfer(tx.origin, quote);

        (bool success, bytes memory returnData) = callContract.delegatecall(callData);
        if (!success) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }

        (, int256 price,,,) = AggregatorV3Interface(ethBasedPriceFeedAddress).latestRoundData();
        uint256 gasUsed = gasInitial - gasleft() + GAS_OVERHEAD;
        uint256 expectedAmount = gasUsed * tx.gasprice * uint256(price) / divisorScale;
        uint256 actualDelta = expectedAmount > quote ? expectedAmount - quote : quote - expectedAmount;
        uint256 actualDeltaBps = actualDelta * 10000 / quote;

        if (actualDeltaBps > maxDelta) {
            revert TransactionOutsideQuote();
        }

        return returnData;
    }
}
