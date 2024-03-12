// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

interface IStandardBridge {
    function bridgeERC20To(
        address _localToken,
        address _remoteToken,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    ) external;
}
