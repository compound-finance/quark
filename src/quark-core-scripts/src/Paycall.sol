// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "quark-core-scripts/src/vendor/chainlink/AggregatorV3Interface.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title Paycall Core Script
 * @notice Core transaction script that can be used to bundle multiple delegatecalls into a single operation
 * @author Compound Labs, Inc.
 */
contract Paycall {
    using SafeERC20 for IERC20;

    error AlreadyInitialized();
    error InvalidCallContext();
    error InvalidInput();
    error MulticallError(uint256 callIndex, address callContract, bytes err);

    /// @notice This contract's address
    address public immutable scriptAddress;

    /// @notice ETH price feed address
    address public immutable ethPriceFeedAddress;

    /// @notice Payment token address
    address public immutable paymentTokenAddress;

    /// @notice Constant buffer for gas overhead
    /// This is a constant to accounted for the gas used by the Paycall contract itself that's not tracked by gasleft()
    uint256 internal constant GAS_OVERHEAD = 75000;

    constructor(address ethPriceFeed, address paymentToken) {
        ethPriceFeedAddress = ethPriceFeed;
        paymentTokenAddress = paymentToken;
        scriptAddress = address(this);
    }

    /**
     * @notice Execute multiple delegatecalls to contracts in a single transaction
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

        (, int256 price,,,) = AggregatorV3Interface(ethPriceFeedAddress).latestRoundData();
        uint256 decimalDiff = uint8(18) + AggregatorV3Interface(ethPriceFeedAddress).decimals()
            - IERC20Metadata(paymentTokenAddress).decimals();
        uint256 gasUsed = gasInitial - gasleft() + GAS_OVERHEAD;
        uint256 paymentAmount = gasUsed * tx.gasprice * uint256(price) / (10 ** uint256(decimalDiff));
        IERC20(paymentTokenAddress).safeTransfer(tx.origin, paymentAmount);

        return returnData;
    }
}
