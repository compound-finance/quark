// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.21;

library ConditionalChecker {
    enum CheckType {
        None,
        Uint,
        Int,
        Bytes,
        Address,
        Bool
    }

    enum Operator {
        None,
        Equal,
        NotEqual,
        GreaterThan,
        GreaterThanOrEqual,
        LessThan,
        LessThanOrEqual
    }

    error CheckFailed(bytes left, bytes right, CheckType cType, Operator op);
    error IncompatibleTypeAndOperator();
    error InvalidOperator();

    function check(bytes memory left, bytes memory right, CheckType cType, Operator op) internal pure {
        bool result;
        if (op == Operator.Equal) {
            result = keccak256(left) == keccak256(right);
        } else if (op == Operator.NotEqual) {
            result = keccak256(left) != keccak256(right);
        } else if (op == Operator.GreaterThan) {
            if (cType == CheckType.Uint) {
                result = abi.decode(left, (uint256)) > abi.decode(right, (uint256));
            } else if (cType == CheckType.Int) {
                result = abi.decode(left, (int256)) > abi.decode(right, (int256));
            } else {
                revert IncompatibleTypeAndOperator();
            }
        } else if (op == Operator.GreaterThanOrEqual) {
            if (cType == CheckType.Uint) {
                result = abi.decode(left, (uint256)) >= abi.decode(right, (uint256));
            } else if (cType == CheckType.Int) {
                result = abi.decode(left, (int256)) >= abi.decode(right, (int256));
            } else {
                revert IncompatibleTypeAndOperator();
            }
        } else if (op == Operator.LessThan) {
            if (cType == CheckType.Uint) {
                result = abi.decode(left, (uint256)) < abi.decode(right, (uint256));
            } else if (cType == CheckType.Int) {
                result = abi.decode(left, (int256)) < abi.decode(right, (int256));
            } else {
                revert IncompatibleTypeAndOperator();
            }
        } else if (op == Operator.LessThanOrEqual) {
            if (cType == CheckType.Uint) {
                result = abi.decode(left, (uint256)) <= abi.decode(right, (uint256));
            } else if (cType == CheckType.Int) {
                result = abi.decode(left, (int256)) <= abi.decode(right, (int256));
            } else {
                revert IncompatibleTypeAndOperator();
            }
        } else {
            // Only reachable if check is called with an invalid operator (None:0)
            revert InvalidOperator();
        }

        if (!result) {
            revert CheckFailed(left, right, cType, op);
        }
    }
}
