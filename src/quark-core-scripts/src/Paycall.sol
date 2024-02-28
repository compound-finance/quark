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

    /// @notice Storage location at which to cache this contract's address
    bytes32 internal constant CONTRACT_ADDRESS_SLOT = keccak256("quark.scripts.paycall.address.v1");

    /// @notice ETH price feed address
    address public immutable ethPriceFeedAddress;

    /// @notice payment token address
    address public immutable paymentTokenAddress;

    /// @notice Constant buffer for gas overhead
    /// This is a constant to accounted for the gas used by the Paycall contract itself that's not tracked by gasleft()
    uint256 internal constant GAS_OVERHEAD = 75000;

    constructor(address ethPriceFeed, address paymentToken) {
        bytes32 slot = CONTRACT_ADDRESS_SLOT;
        ethPriceFeedAddress = ethPriceFeed;
        paymentTokenAddress = paymentToken;

        assembly ("memory-safe") {
            sstore(slot, address())
        }
    }

    /**
     * @notice Execute multiple delegatecalls to contracts in a single transaction
     * @param paycallScriptAddress Address of the paycall script (need for access pricefeed and payment token initiated in consturctor() due to callcode can't access the paycall storages directly)
     * @param callContract Contract to call
     * @param callData Encoded calldata for call
     * @return Return data from call
     */
    function run(address paycallScriptAddress, address callContract, bytes calldata callData)
        external
        returns (bytes memory)
    {
        uint256 gasInitial = gasleft();
        bytes32 slot = CONTRACT_ADDRESS_SLOT;
        address thisAddress;
        assembly ("memory-safe") {
            thisAddress := sload(slot)
        }

        if (address(this) == thisAddress) {
            revert InvalidCallContext();
        }

        address ethPriceFeed = Paycall(paycallScriptAddress).ethPriceFeedAddress();
        address paymentToken = Paycall(paycallScriptAddress).paymentTokenAddress();

        (bool success, bytes memory returnData) = callContract.delegatecall(callData);
        if (!success) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }

        (, int256 price,,,) = AggregatorV3Interface(ethPriceFeed).latestRoundData();
        uint256 decimalDiff =
            uint8(18) + AggregatorV3Interface(ethPriceFeed).decimals() - IERC20Metadata(paymentToken).decimals();
        uint256 gasUsed = gasInitial - gasleft() + GAS_OVERHEAD;
        uint256 paymentAmount = gasUsed * tx.gasprice * uint256(price) / (10 ** uint256(decimalDiff));
        IERC20(paymentToken).safeTransfer(tx.origin, paymentAmount);

        return returnData;
    }
}
