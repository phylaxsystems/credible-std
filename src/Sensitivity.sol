// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title Sensitivity
/// @notice How aggressively an anomaly trigger fires, as a level rather than a threshold.
/// @dev Each level is a point on the detector's recall-versus-false-positive curve, fixed to a
///      false-positive budget that is the same on every contract:
///
///      | Level | 1     | 2     | 3     | 4    | 5    | 6    | 7  | 8  | 9  | 10  |
///      | ----- | ----- | ----- | ----- | ---- | ---- | ---- | -- | -- | -- | --- |
///      | Fires on | 0.01% | 0.02% | 0.05% | 0.1% | 0.2% | 0.5% | 1% | 2% | 5% | 10% |
///
///      Higher is more sensitive: it catches more, and fires on more benign traffic. The
///      *threshold* behind a level is resolved per contract, from that contract's own history,
///      where the trigger is evaluated. One level therefore means one budget everywhere, and a
///      retrain moves the threshold without touching this code.
///
///      An assertion never names a basis-point score for that reason. A threshold belongs to one
///      contract and one model version; copy it to a second contract, or keep it across a retrain,
///      and the trigger mis-configures in the direction that hurts. It stops firing while still
///      looking healthy.
///
///      Firing is not blocking. A trigger that fires runs the assertion, and the assertion decides.
///      Pair an anomaly trigger with a damage check and only what is both unusual *and* doing
///      damage gets blocked. See `src/protection/anomaly`.
library Sensitivity {
    /// @notice Fires on 0.01% of this contract's transactions. Catches the least.
    uint8 internal constant LEVEL_1 = 1;
    uint8 internal constant LEVEL_2 = 2;
    uint8 internal constant LEVEL_3 = 3;
    uint8 internal constant LEVEL_4 = 4;
    uint8 internal constant LEVEL_5 = 5;
    uint8 internal constant LEVEL_6 = 6;
    /// @notice Fires on 1% of this contract's transactions. The recommended operating point.
    uint8 internal constant LEVEL_7 = 7;
    uint8 internal constant LEVEL_8 = 8;
    uint8 internal constant LEVEL_9 = 9;
    /// @notice Fires on 10% of this contract's transactions. Catches the most.
    uint8 internal constant LEVEL_10 = 10;

    /// @notice The recommended level for a protocol without a reason to choose otherwise.
    uint8 internal constant RECOMMENDED = LEVEL_7;

    /// @notice The strictest level, and the loosest, the bounds a valid level lies within.
    uint8 internal constant MIN = LEVEL_1;
    uint8 internal constant MAX = LEVEL_10;

    /// @notice Whether `level` names a rung of the ladder.
    /// @dev `0` is not a level: it is the "cleared nothing" sentinel an unscored target reads
    ///      back in `PhEvm.AnomalyContext.firesAt`.
    function isValid(uint8 level) internal pure returns (bool) {
        return level >= MIN && level <= MAX;
    }
}
