// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

import "quark-core-scripts/src/vendor/chainlink/AggregatorV3Interface.sol";
import "quark-core-scripts/src/lib/ERC20.sol";
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

    /// @notice Storage location at which to cache this contract's address
    bytes32 internal constant CONTRACT_ADDRESS_SLOT = keccak256("quark.scripts.multicall.address.v1");

    /// @notice Storage location for the ETH price oracle address
    bytes32 internal constant ETH_PRICE_FEED_SLOT = keccak256("quark.scripts.multicall.ethPriceFeed.v1");

    /// @notice Storage location for the payment token address
    bytes32 internal constant PAYMENT_TOKEN_SLOT = keccak256("quark.scripts.multicall.paymentToken.v1");

    /// @notice Constant buffer for gas overhead
    uint256 internal constant GAS_OVERHEAD = 21000;

    constructor(address ethPriceFeed, address paymentToken) {
        bytes32 slot = CONTRACT_ADDRESS_SLOT;
        bytes32 priceFeedSlot = ETH_PRICE_FEED_SLOT;
        bytes32 paymentTokenSlot = PAYMENT_TOKEN_SLOT;
        assembly ("memory-safe") {
            sstore(slot, address())
            sstore(priceFeedSlot, ethPriceFeed)
            sstore(paymentTokenSlot, paymentToken)
        }
    }

    /**
     * @notice Execute multiple delegatecalls to contracts in a single transaction
     * @param callContract Contract to call
     * @param callData Encoded calldata for call
     * @return Return data from call
     */
    function run(address callContract, bytes calldata callData) external returns (bytes memory) {
        uint256 gasInitial = gasleft();
        bytes32 slot = CONTRACT_ADDRESS_SLOT;
        bytes32 ethPriceFeedSlot = ETH_PRICE_FEED_SLOT;
        bytes32 paymentTokenSlot = PAYMENT_TOKEN_SLOT;
        address thisAddress;
        address ethPriceFeed;
        address paymentToken;
        assembly ("memory-safe") {
            thisAddress := sload(slot)
            ethPriceFeed := sload(ethPriceFeedSlot)
            paymentToken := sload(paymentTokenSlot)
        }

        if (address(this) == thisAddress) {
            revert InvalidCallContext();
        }

        (bool success, bytes memory returnData) = callContract.delegatecall(callData);
        if (!success) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }

        (, int price, , , ) = AggregatorV3Interface(ethPriceFeed).latestRoundData();
        uint256 decimalDiff = uint8(18) + AggregatorV3Interface(ethPriceFeed).decimals() - IERC20Metadata(paymentToken).decimals();
        uint256 gasUsed = gasInitial - gasleft() + GAS_OVERHEAD;
        uint256 paymentAmount = gasUsed * tx.gasprice * uint256(price) / (10**uint256(decimalDiff));
        IERC20(paymentToken).safeTransfer(tx.origin, paymentAmount);

        return returnData;
    }
}
