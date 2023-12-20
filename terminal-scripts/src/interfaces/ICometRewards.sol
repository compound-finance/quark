// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

interface ICometRewards {
    function claim(address comet, address src, bool shouldAccrue) external;
}
