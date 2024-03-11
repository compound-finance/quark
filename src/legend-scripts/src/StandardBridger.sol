pragma solidity 0.8.23;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

interface StandardBridge {
    function bridgeERC20To(
        address _localToken,
        address _remoteToken,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    ) external;
}

contract StandardBridger {
    StandardBridge immutable bridge;

    constructor(StandardBridge bridge_) {
        bridge = bridge_;
    }

    /**
     *   @notice Bridge token over standard bridge.
     */
    function bridgeToken(address localToken,
            address remoteToken,
            address to,
            uint256 amount,
            uint32 minGasLimit,
            bytes calldata extraData) external {
        IERC20(localToken).approve(address(bridge), amount);
        bridge.bridgeERC20To(localToken, remoteToken, to, amount, minGasLimit, extraData);
    }
}
