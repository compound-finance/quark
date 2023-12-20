// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

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

    struct Condition {
        CheckType checkType;
        Operator operator;
    }

    error CheckFailed(bytes left, bytes right, CheckType cType, Operator op);
    error IncompatibleTypeAndOperator();
    error InvalidOperator();

    function check(bytes memory left, bytes memory right, Condition memory cond) internal pure {
        bool result;
        if (cond.operator == Operator.Equal) {
            result = keccak256(left) == keccak256(right);
        } else if (cond.operator == Operator.NotEqual) {
            result = keccak256(left) != keccak256(right);
        } else if (cond.operator == Operator.GreaterThan) {
            if (cond.checkType == CheckType.Uint) {
                result = abi.decode(left, (uint256)) > abi.decode(right, (uint256));
            } else if (cond.checkType == CheckType.Int) {
                result = abi.decode(left, (int256)) > abi.decode(right, (int256));
            } else {
                revert IncompatibleTypeAndOperator();
            }
        } else if (cond.operator == Operator.GreaterThanOrEqual) {
            if (cond.checkType == CheckType.Uint) {
                result = abi.decode(left, (uint256)) >= abi.decode(right, (uint256));
            } else if (cond.checkType == CheckType.Int) {
                result = abi.decode(left, (int256)) >= abi.decode(right, (int256));
            } else {
                revert IncompatibleTypeAndOperator();
            }
        } else if (cond.operator == Operator.LessThan) {
            if (cond.checkType == CheckType.Uint) {
                result = abi.decode(left, (uint256)) < abi.decode(right, (uint256));
            } else if (cond.checkType == CheckType.Int) {
                result = abi.decode(left, (int256)) < abi.decode(right, (int256));
            } else {
                revert IncompatibleTypeAndOperator();
            }
        } else if (cond.operator == Operator.LessThanOrEqual) {
            if (cond.checkType == CheckType.Uint) {
                result = abi.decode(left, (uint256)) <= abi.decode(right, (uint256));
            } else if (cond.checkType == CheckType.Int) {
                result = abi.decode(left, (int256)) <= abi.decode(right, (int256));
            } else {
                revert IncompatibleTypeAndOperator();
            }
        } else {
            // Only reachable if check is called with an invalid operator (None:0)
            revert InvalidOperator();
        }

        if (!result) {
            revert CheckFailed(left, right, cond.checkType, cond.operator);
        }
    }
}
