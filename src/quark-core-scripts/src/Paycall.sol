// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "quark-core-scripts/src/vendor/chainlink/AggregatorV3Interface.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title Paycall Core Script
 * @notice Paycall script that can be used to execute actions via delegatecall and pay for gas in a single transaction, by sending to the tx.origin
 * @author Compound Labs, Inc.
 */
contract Paycall {
    using SafeERC20 for IERC20;

    error InvalidCallContext();

    /// @notice This contract's address
    address internal immutable scriptAddress;

    /// @notice ETH based price feed address (i.e. ETH/USD, ETH/BTC)
    address public immutable ethBasedPriceFeedAddress;

    /// @notice Payment token address
    address public immutable paymentTokenAddress;

    /// @notice Constant buffer for gas overhead
    /// This is a constant to accounted for the gas used by the Paycall contract itself that's not tracked by gasleft()
    uint256 internal constant GAS_OVERHEAD = 75000;

    /// @notice Decimal difference between the payment token and ETH
    /// Will be used to scale decimals to the correct amount for payment token
    uint256 internal immutable divisorScale;

    /**
     * @notice Constructor
     * @param ethPriceFeed Eth based price feed address that follows Chainlink's AggregatorV3Interface correlated to the payment token
     * @param paymentToken Payment token address
     */
    constructor(address ethPriceFeed, address paymentToken) {
        ethBasedPriceFeedAddress = ethPriceFeed;
        paymentTokenAddress = paymentToken;
        scriptAddress = address(this);

        divisorScale = 10
            ** uint256(
                uint8(18) + AggregatorV3Interface(ethBasedPriceFeedAddress).decimals()
                    - IERC20Metadata(paymentTokenAddress).decimals()
            );
    }

    /**
     * @notice Execute delegatecall to contracts and pay tx.origin for gas
     * @param callContract Contract to call
     * @param callData Encoded calldata for call
     * @return Return data from call
     */
    function run(address callContract, bytes calldata callData) external returns (bytes memory) {
        uint256 gasInitial = gasleft();
        if (address(this) == scriptAddress) {
            revert InvalidCallContext();
        }

        (bool success, bytes memory returnData) = callContract.delegatecall(callData);
        if (!success) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }

        (, int256 price,,,) = AggregatorV3Interface(ethBasedPriceFeedAddress).latestRoundData();
        uint256 gasUsed = gasInitial - gasleft() + GAS_OVERHEAD;
        uint256 paymentAmount = gasUsed * tx.gasprice * uint256(price) / divisorScale;
        IERC20(paymentTokenAddress).safeTransfer(tx.origin, paymentAmount);

        return returnData;
    }
}
